---
spec_id: SDD-JDBC-DIRECT-V3
revision: 1
status: frozen
base_ref: 94864edb4 (engine, branch codex/jdbc-direct-phase3) + 4b539be (cubrid-jdbc submodule)
---

# Goal

CUBRID JDBC direct prepared execution protocol v3: 기존 v2(SELECT 전용)를 확장해
auto-commit **UPDATE/INSERT/DELETE의 direct 실행**, **접속 사용자 전달**, **확장 scalar
type**, **서버 에러 message 전달**, **XASL 무효화 자동 복구**를 제공한다. 모든 비적격
statement는 기존 CAS 경로가 default branch로 실행한다(의미 동일, 경로만 다름).

# In scope

Engine (worktree of https://github.com/xmilex-git/cubrid, base 94864edb4):

- `src/communication/network_interface_sr.cpp` — attach/execute handler
- `src/communication/network.h`, `src/communication/network_sr.c`,
  `src/communication/network_interface_sr.h` — opcode 등록(기존 2개 유지)
- `src/broker/cas_execute.c` — `ux_jdbc_direct_poc_take_xasl` 적격성 확장
- `src/base/system_parameter.c`, `src/base/system_parameter.h` — 세션 파라미터
  기본값 배열 생성 helper 1개 추가

JDBC (submodule cubrid-jdbc, base 4b539be):

- `src/jdbc/cubrid/jdbc/jci/UDirectPocConnection.java`
- `src/jdbc/cubrid/jdbc/jci/UStatement.java`
- `src/jdbc/cubrid/jdbc/jci/UConnection.java`
- `src/jdbc/cubrid/jdbc/jci/UClientSideConnection.java`

# Out of scope

- explicit transaction의 direct 실행, batch, generated keys, cursor/page fetch,
  NUMERIC/날짜시간/LOB/SET type, cancel/queryTimeout의 direct 지원(비적격 강등 유지)
- 위 In-scope 외 파일의 제품 변경(빌드 파일 포함)
- 성능 최적화(측정은 하되 합격 문턱 없음)

# Protocol v3 (normative)

공통: 모든 정수는 big-endian 4바이트(int64/double은 8바이트), 가변 payload는 4바이트
경계로 zero-padding. 상수: opcode ATTACH=189, EXECUTE=190 (기존 유지),
PROTOCOL_VERSION=3. version 불일치는 협상 없이 오류(fail-fast).

## ATTACH request/reply

- request: `{int version=3, int user_len(0..256), byte[user_len] db_user(UTF-8), pad4}`
  - `user_len==0`이면 서버는 `"PUBLIC"`을 사용한다.
  - 서버는 db_user를 `xboot_register_client` 표준 credential 경로로 등록한다
    (password 검증은 broker 접속 시 CAS의 `au_login`이 이미 수행 — ADR 0003).
  - 등록 성공 시 `xsession_create_new`로 세션 생성 **후 반드시 서버측 기본값으로
    session parameters를 세션에 바인딩**한다(미바인딩 시 세션 스코프 prm을 읽는
    실행 경로가 크래시한다 — 예: `check_hash_list_scan`). 실패 시 등록을 되돌린다.
- reply: `{int version, int status(0=OK else errid), int tran_index(-1=fail)}`
  - reply 버퍼 포인터는 요청 파싱에 쓴 포인터와 별개로 reply 시작으로 초기화할 것.
- 형식 위반(길이 불일치, user_len 범위 밖, version≠3, 이미 attach된 연결)은
  status!=0 응답, 크래시 금지.

## EXECUTE request

`{int version=3, int stmt_kind, XASL_ID(28B), int param_count(0..64), param TLV*}`

- `stmt_kind`: 0=SELECT, 1=DML(UPDATE/INSERT/DELETE). 그 외 값은 오류.
  서버는 결과 list 모양으로 statement 종류를 **추론하지 않는다**
  (UPDATE/DELETE의 결과 list는 내부 OID 컬럼(type_cnt=1)을 가질 수 있다).
- param TLV: `{int type_tag, int byte_len, payload pad4}`
  - tag: NULL=0(len 0), INT=1(len 4), VARCHAR=2(len n, connection charset bytes),
    BIGINT=3(len 8), SHORT=4(len 4, int로 widen), FLOAT=5(len 4, IEEE754 BE),
    DOUBLE=6(len 8, IEEE754 BE). CHAR=7은 결과 전용(요청에 오면 오류).
- 경계 검사(모두 status!=0 응답 + 서버/연결 생존):
  - len<0 또는 len>1MiB 거부(정수 overflow 가드 겸용)
  - 포인터 비교는 overflow-safe 형태(`remaining < needed`)로만
  - 마지막 param 뒤 trailing bytes 존재 시 거부
  - param_count가 CAS prepare의 host var 수와 불일치하면 오류

## EXECUTE reply

`{int version, int status, int tran_state, int affected_rows, int row_count, int col_count}`
+ payload:

- status!=0: `{int msg_len(0..4096), msg bytes pad4}` — 서버 스레드의 에러 message를
  **commit/abort 처리 전에 캡처**해 싣는다(캡처 없으면 msg_len 0).
  row_count=col_count=0, affected_rows=-1.
- status==0, stmt_kind=DML: affected_rows = 실행 결과 list의 `tuple_cnt`,
  row/col=0, payload 없음. 결과 list의 내부 컬럼은 직렬화하지 않는다.
- status==0, stmt_kind=SELECT: affected_rows=-1, row_count×col_count 값 TLV.
  값 tag는 요청과 동일 + CHAR=7. 허용 결과 컬럼 type: INT/SHORT/BIGINT/FLOAT/
  DOUBLE/CHAR/VARCHAR(+NULL 값). 그 외 type은 오류.
  응답 상한 1MiB — 각 값 **삽입 전에** 검사(일시적 초과 할당 금지, silent
  truncation 금지).
- 실행: `xqmgr_execute_query` + `TRAN_AUTO_COMMIT|EXECUTE_QUERY_WITH_COMMIT`,
  handler 내 동기 완결(실행→직렬화→end query→commit/abort), 실패 시 rollback.
  DML 오류(제약 위반 등) 후에도 연결과 서버는 정상이어야 한다.

## take_xasl (CAS) 적격성 — 모두 만족해야 XASL 반환, 아니면 CAS_ER_ARGS 거절

1. statement pooling ON (OFF면 CAS auto-commit마다 handle이 해제되어 fallback 파손)
2. stmt_type ∈ {SELECT, UPDATE, DELETE, INSERT}
3. `statement->xasl_id` 존재
4. `parser->auto_param_count == 0` (auto-parameterized 리터럴은 direct bind 수와
   불일치)
5. server-side DML만: `info.update.server_update`, `info.delete_.server_delete`,
   `info.insert.server_allowed == SERVER_INSERT_IS_ALLOWED`
6. srv handle은 해제하지 않고 유지(강등 fallback + close 1회 계약)

## JDBC 적격성/강등 (모두 기존 CAS 코드가 default branch)

- prepare 시: property opt-in AND pooling ON AND 후보 statement AND 유효
  isolation == TRAN_READ_COMMITTED(첫 판정 시 GET_DB_PARAMETER로 해석·캐시).
  take_xasl의 CAS_ER_ARGS 거절만 조용한 강등; 그 외 오류는 전파.
- execute 시: directXaslId 존재 AND autoCommit AND isolation 캐시 일치 AND
  의미 비보존 옵션 없음(maxRows/maxFieldSize/scrollable/sensitive/queryPlan/
  onlyPlan/executeAll/async/queryTimeout>0) AND 지원 bind type
  (String/Integer/Short/Long/Float/Double/null).
- 후보 statement: SELECT(결과 컬럼 type 전부 허용 집합) 또는 DML.
- 결과 주입: SELECT는 per-column charset으로 디코딩(CAS fetch와 동일),
  DML은 executeResult=affected(executeUpdate() 반환값 일치).
- 서버 status!=0은 **DBMS 오류**(errid+message 포함 SQLException)로 표면화 —
  ER_COMMUNICATION/재접속 경로 금지. 단 `-452`(ER_QPROC_INVALID_XASLNODE)는
  재prepare(reset) 후 direct 1회 재시도, 재실패 시 DBMS 오류.
  reset 후 directXaslId는 재prepare 결과로 갱신되어야 한다.
- direct socket 자체의 IO 실패는 기존 통신 오류 경로 유지.

# Acceptance criteria

- AC-001: direct URL 접속 시 서버 tranlist에 접속 db_user로 등록된다. 구버전
  (payload 없는) attach는 오류 응답을 받고 서버는 생존한다.
- AC-002: WHERE절 있는 UPDATE/DELETE의 direct 실행이 서버 크래시 없이 동작한다
  (세션 파라미터 바인딩 증명; core 파일 0).
- AC-003: malformed request 9종(버전/절단/태그/음수 len/거대 len/절단 payload/
  trailing/param 초과/가짜 XASL)이 전부 오류 응답을 받고 직후 정상 direct 실행이
  성공한다.
- AC-004: SELECT parity — INT/SHORT/BIGINT/FLOAT/DOUBLE/CHAR/VARCHAR/NULL 컬럼과
  한글 VARCHAR, multi-row, 숫자 bind 4종이 CAS 결과와 문자열 동일.
- AC-005: direct INSERT/UPDATE/DELETE의 executeUpdate() 반환값이 CAS와 동일
  (1/0/다중행)하고 CAS 연결로 조회한 영속 상태가 일치하며, direct DML 실행
  N회의 broker QPS 증가가 (N이 아니라) 상수(≤5)다.
- AC-006: 중복 PK INSERT가 서버 message를 포함한 SQLException으로 실패하고
  트랜잭션은 롤백되며 같은 connection이 계속 사용 가능하다.
- AC-007: 같은 PreparedStatement 실행 사이에 ALTER TABLE이 끼어도 다음 실행이
  재prepare 재시도로 성공하고 결과가 옳다.
- AC-008: 강등 정합 — serializable isolation/autoCommit=false/maxRows/미지원
  bind·컬럼 type/pooling OFF 각각에서 결과는 CAS와 동일하고, 강등 케이스의
  broker QPS는 실행 횟수만큼 증가하며 direct 케이스는 상수다.
- AC-009: 순수 CAS URL의 전체 스위트가 base와 동일하게 PASS(회귀 0),
  diff는 In-scope 파일에 한정된다.
- AC-010: 스위트+churn(2만 prepare/close) 후 `ER_SES_SESSION_EXPIRED` 0,
  tranlist에 direct client 잔존 0, cub_cas RSS 증가 <2MB, 서버 err log flood 없음.
- AC-011: YCSB workload A와 B가 direct URL에서 ERR=0으로 완주한다(2/32 threads,
  각 20s; throughput은 보고만).
- AC-012: `git diff --check` clean (engine/JDBC 모두).

# Constraints

- 빌드: tooling repo에서 `WORKSPACE=<worktree> just build jdbc-direct-poc-release <version>`
  (cubrid-build skill). 서버 제어는 cubrid-server-control skill 래퍼만.
- 재설치가 conf를 리셋하므로 매 설치 후 `data_buffer_size=8G`(cubrid.conf),
  BROKER1 `SQL_LOG=OFF` 재적용, `databases.txt`에 ycsb 등록 확인.
- 서버 stop 실패 시 stale binary로 검증 금지 — cub_server 시작시각으로 확인.
- direct hot path에 process-global 동기화(예: synchronized static) 추가 금지.
- 스크래치는 tooling repo `.git_ignored_dir/scratch/`만 사용, /tmp 금지.

# Verification

하네스(컨트롤러 소유, 수정 금지 — 결함 발견 시 T-discrepancy로 보고):
`/home/cubrid/dev/workspace/.git_ignored_dir/scratch/jdbc-direct-smoke/`
(Smoke.java, Smoke3.java, Smoke4.java, malformed.py, DemoteProbe.java,
DmlProbe.java, Probe.java, ConnChurn.java), YCSB:
`/home/cubrid/dev/workspace/.git_ignored_dir/scratch/ycsb/` (5M rows DB 포함).

- AC-001: `cubrid tranlist ycsb` 중 direct 접속 상태에서 user 확인 +
  `python3 <(구버전 attach 스크립트)` — malformed.py의 attach 실패 케이스
- AC-002: `java Smoke4 ycsb` (direct-update-*, direct-delete-*) + `ls core.*` 없음
- AC-003: `python3 malformed.py ycsb` → `MALFORMED_ALL_PASS`
- AC-004: `java Smoke ycsb` + `java Smoke4 ycsb`(type-expansion, numeric-bind)
- AC-005: `java Smoke4 ycsb`(insert/update/delete) + `java DmlProbe <direct-url> 200`
  전후 `cubrid broker status -b -f` QPS delta ≤5 (CAS url 대조군 ≈201)
- AC-006: `java Smoke4 ycsb`(direct-constraint-*)
- AC-007: `java Smoke4 ycsb`(xasl-invalidation-retry)
- AC-008: `java Smoke3 ycsb 20000` + DemoteProbe 3모드 QPS delta + pooling OFF
  전환 후 DemoteProbe direct 모드 QPS delta ≈ N
- AC-009: CAS URL로 Smoke/Smoke3/Smoke4의 CAS-side 검증 + `git diff --stat`
- AC-010: Smoke3 churn 후 `ps -C cub_cas -o rss=` delta, `cubrid tranlist`,
  `grep -c SESSION_EXPIRED <server err>` == 0
- AC-011: YCSB `bash bin/ycsb.sh run jdbc -P workloads/workload{a,b} ...`
  (dml-gate 디렉토리의 기존 명령과 동일) → `Return=ERROR` 없음
- AC-012: `git diff --check`

# Open questions

- None.
