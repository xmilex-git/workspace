# cas-merge upstream CI test_shell 전수 실패 분석 (CUBRID/cubrid#7837, CircleCI 151311)

> 2026-09-02 로그 분석(재현 없음). 선행 CTP 결함 추적 티켓의 코멘트 4건을 그대로 옮긴 것. 새 맵의 'CI test_shell 게이트' 티켓 입력.

===== 2026-09-02T05:38:45Z https://github.com/xmilex-git/workspace/issues/176#issuecomment-5504979600
**wf-CI — upstream `test_shell` 전수 실패 분석 (CUBRID/cubrid#7837, CircleCI 151311) — 로그 분석만, 재현 없음**

### 0. 추적 기준점 (나중에 고칠 때 이 커밋 조합으로 재현)

| 항목 | 값 |
|---|---|
| 엔진 PR | [CUBRID/cubrid#7837](https://github.com/CUBRID/cubrid/pull/7837) `cas-merge` head **`7117c8a663f4a4734d0c84ded857f94c6cf23315`** (wf143 _22_ha closure 커밋) |
| 엔진 PR이 뿌리로 둔 develop | **`5ae45603f`** — 2026-08-31 `[CBRD-27294] Fix DISTINCT aggregate/analytic ... (#7772)` (`git merge-base pull/7837/head develop`) |
| CI 시점 develop tip (참고) | `1ea077d85` `[CBRD-27308] (#7792)` — merge-base 이후 develop에 5커밋 더 있음(3448e3c5a CBRD-26770 CAS SQL log, c85367270, 45aa81034, a64ba7ab9 CBRD-27306, 1ea077d85). PR 브랜치에는 **미반영**. CircleCI는 merge 커밋이 아니라 `pull/7837/head` 그대로 빌드함 |
| TC PR | [cubrid-testcases-private-ex#4040](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4040) `tc/pr-7837` head **`408ef8f1b`** (커밋 1개 `chore: Initialize TC branch for PR #7837`, 내용 변경 없음) |
| TC PR이 뿌리로 둔 develop | **`e719a8d37`** — 2026-08-31 `[CBRD-27300] Add shell testcase for digit-leading hostnames (#3998)`. 즉 TC 내용은 develop@e719a8d37과 동일 |
| CI 시점 TC develop tip (참고) | `49efa45b6` `[CBRD-27306] Re-baseline bug_bts_9967 plan dump (#3980)` — TC develop은 merge-base 이후 4커밋 앞섬. (bug_bts_9967 재기준선은 엔진 #7787과 짝이므로 지금 PR/TC 조합에서는 둘 다 없는 상태로 일관됨) |
| testtools | cubrid-testtools develop `a1bec8762` |
| 빌드 | `11.5.0.2738-7117c8a` 64bit **optdebug** (GlusterFS `/home/build-cache/builds/7117c8a.../debug`) |
| CircleCI | workflow `build_test` `323c78f8-9a36-45af-9e51-342e6feb5a91` / job `test_shell` **151311** (https://circleci.com/gh/CUBRID/cubrid/151311), 2026-09-02 02:51 KST 시작, 75분, parallelism 50 |

### 1. 결과 총량

| 항목 | 값 |
|---|---|
| 노드 | 50 / 50 실패 (48 `failed`, **2 `timedout`**: node 2, node 29) |
| 배정 TC | 3,222 |
| CircleCI 집계 | 3,105건 = **OK 2,704 / NOK 372 / skip 29** |
| **미실행** | **105건** (node 2: 50, node 29: 55) — hang 테스트 1건씩이 1200s 워치독에 걸린 뒤 노드 전체가 timeout으로 종료됨. 두 노드가 hang 전에 실행한 22건은 결과 업로드 실패로 집계에서 빠짐(전부 OK) |
| 코어 | ERROR_BACKUP 15건, 코어 파일 **18개** (cub_server 13, cub_manager 2, TC 클라이언트 바이너리 3) |

NOK 372건을 로그만으로 전수 분류했다(카테고리별 테스트 표는 아래 부록 코멘트 2건). 판정 열은 로그 근거만으로 낸 1차 판정이며 **재현·코드 확인은 하지 않았다**.

### 2. 카테고리 요약

| # | 카테고리 | 건수 | 1차 판정 | 의심 코드 영역 |
|---|---|---|---|---|
| A | CAS 프로세스 모델 가정 (cub_cas 프로세스·per-CAS sql_log·broker status 열·MIN/MAX_NUM_APPL_SERVER) | **129** (+hang 2, 미실행 105 유발) | 대부분 TC측 비호환(설계 변경 #116 D9/D10). 단 hang 2건은 제품이 무한 대기 조건을 준 것이므로 TC 수정 필요 | `src/broker/broker_monitor.c`(status), `broker_admin_pub.c`(direct-handoff 거부), sql_log 미생성 |
| B | 직결 CS 클라이언트 / CDC API 접속 실패 | **64** | **PRODUCT 의심(단일 근인)** | `src/api/cubrid_log.c` `css_connect_to_log_server` → 서버 수용 경로(`master_connector.cpp`/`server_support.c`), libcubridcs `db_restart` 직결 |
| C | thin csql 동작 차이 | **58** | PRODUCT 32 / TC 6 / 미정 20 | `src/executables/csql*`, `csql_wire.c` — `;plan detail`, `;.h`(histogram), `Statistics updated successfully`, isolation 메시지, csql.err 기록 |
| D | SHARD 제거 | **41** | 의도된 제거(#116 D2) → TC 제외 대상 | `src/broker/broker_config.c:1322` `SHARD is not supported` |
| E | 서버측 SQL/메시지 차이 | **21** | PRODUCT 다수 | 트리거 `execute print`, `block_ddl_statement`, `SET SYSTEM PARAMETERS` 세션 지속, XASL 캐시 `sql user text` 후행 `;`, plandump |
| F | 행/타임아웃 | **17** (+노드 hang 2) | PRODUCT 의심 11(plcsql isolation) / 미정 6 | 세션 간 가시성/락 대기, JDBC 대량 커넥션 |
| G | 접속 경로(adoption) 에러 텍스트/코드 변화 | **13** | PRODUCT(에러코드·메시지 호환) | `src/connection/adoption.cpp`, `driver_session.cpp`, 브로커→서버 handoff 에러 프레임 |
| H | 크래시(코어) | **8** (코어 18) | **PRODUCT** (fault-injection 1건 제외) | `xqmgr_execute_query`(query_manager.c:1635) 컴파일-시 서브쿼리 실행, cub_manager `er_clear` TLS, 미해독 cub_server 코어 4종 |
| I | PL/CSQL·JavaSP | 3 | 미정 | 중첩 호출 깊이/에러 전파, owners-rights 트리거 출력 |
| J | HA | 1 | 미정 | cci_applier 실패 감지 |
| K | 환경/플래키 | 1 | TC/환경 | itrack_10011 잔존 볼륨 파일 |
| L | 미분류 | 16 | — | 로그 부족(콘솔 미캡처 5건) 또는 시간 내 미분석 |

### 3. 카테고리별 상세

#### A. CAS 프로세스 모델 가정 — 129건 + 노드 hang 2건
- **시그니처(빈도순)**: ① per-CAS `sql_log`(`<broker>_1.sql.log`) 파일이 생성되지 않음 → broker_log_top / broker_log_converter / `query_cancel` / `end_tran ROLLBACK` grep 전부 실패 (가장 많음, _06_issues 전반) ② `cubrid broker status [-f|-b]`에 CAS 행(IDLE/BUSY/CLIENT/요청수)이 없음 ③ `cubrid broker add|drop|restart <br>`·`broker_changer SQL_LOG|SLOW_LOG|APPL_SERVER_MAX_SIZE|LONG_QUERY_TIME…`가 `is a direct-handoff front (no CAS pool)` / `CAS execution parameters are server parameters (cas_*)`로 거부 ④ `killtran`/`tranlist`/`show access status`에 프로그램명이 `cub_cas`/`csql`가 아니라 `driver_session` ⑤ `ps -f | grep <br>_cub_cas_N`, `$CUBRID/var/CUBRID_SOCK/<br>.N` 소켓 부재 ⑥ `_08_shard` 외의 `_06_issues/_14_1h` 등에 섞인 CAS 로그 기대 TC.
- **노드 hang 2건(제품이 무한루프 조건 제공)**: `_06_issues/_12_2h/bug_bts_7558` — `while idle<2: cubrid broker status | grep IDLE` 무한 대기(node 2), `_06_issues/_11_1h/bug_bts_4321_2` — `while [ -z $cas_num ]: cubrid broker status -f | grep $dbname` 무한 대기(node 29). 두 건이 각 노드의 나머지 **105건 미실행**을 유발했다. 다음 CI 전에 이 두 TC는 반드시 제외/수정해야 나머지 결과를 볼 수 있다.
- **판정**: 설계상 없어진 구조를 세는 TC(#116 D1/D9/D10 확정 사항) → TC측. 단, `driver_session` 프로그램명(④)과 `broker status` 출력 형식은 운영 호환성 관점에서 제품 결정이 필요(별건).

#### B. 직결 CS 클라이언트 / CDC API — 64건 (PRODUCT 의심, 단일 근인)
- `_37_elderberry/cbrd_23842_cdc/**` 60건 전부: 테스트 C 바이너리의 `cubrid_log_connect_server(host, port, db, "dba", "")`가 **일괄 `rc=-10 (CUBRID_LOG_FAILED_CONNECT)`**. cbrd_27022는 300회 재시도 전부 실패로 "환경 문제"라고 스스로 표시. `_37_elderberry` 160건 중 64건 실패의 원인이 이것 하나다.
- 같은 뿌리로 보이는 것: `_03_itrack/itrack_1001685`(libcubridcs `db_restart()` 직결 실패), `_06_issues/.../bug_bts_5097`(직결 클라이언트 `obj` 무출력), `_05_addition/bug_cubridsus2023`(직결 C 클라이언트 `active_query`가 `db_query_end_internal` db_query.c:3653에서 SIGSEGV, `result=0x74006500000020` 쓰레기 포인터, `error=-224`), `_06_issues/_25_2h/cbrd_26247`(**cub_manager**가 `db_restart` 중 `cuberr::context::get_thread_local_context` error_context.cpp:342 assert → abort, 코어 2개).
- **해석**: 브로커를 거치지 않고 cub_server(master 포트)에 직접 붙는 레거시 CS 경로(CDC 로그 스트리밍, cub_manager, C API 직결 프로그램)가 폴드 후 서버측에서 수용되지 않거나 다른 프로토콜로 응답하는 것으로 보인다. `src/api/cubrid_log.c`는 PR에서 변경되지 않았고 `src/connection/{adoption,driver_session}.cpp`·`server_support.c`가 신규/변경됨. **CDC는 제품 기능이므로 반드시 제품측 수정 필요**.

#### C. thin csql 동작 차이 — 58건
- **`;plan detail` 무출력** 약 15건(`_35_cherry`·`_06_issues`의 PrintInfo.exp 계열: Join graph/Query plan 텍스트가 전혀 안 나옴) — PRODUCT.
- **histogram 세션커맨드** 약 12건: `;.h on`/`;xr`/`;.x`가 `Histogram commands are not supported by this csql.` 또는 무동작, `Num_data_page_fetches`·`SERVER EXECUTION STATISTICS` 블록 부재, 비-DBA에 대한 `Histogram is allowed only for DBA` 미출력 — thin csql이 의도적으로 뺀 기능이면 TC 제외, 아니면 PRODUCT. 결정 필요.
- **`Statistics updated successfully: N table, M columns.` 확인 메시지 미출력** 5건(+E의 plandump 4건) — 클라이언트측 메시지가 서버측 실행으로 옮겨가며 사라짐. PRODUCT.
- **isolation/세션 메시지**: `Isolation level set to: …` 미출력, `;ge intl_date_lang` 등 세션 파라미터 GET 불일치, `lock_timeout` 항상 -1, `SET TRANSACTION ISOLATION LEVEL` 확인문 부재.
- **csql.err 기록**: 서버 종료 시 disconnect 메시지, invalid isolation 텍스트, `SET autocommit off` 에러 등이 csql.err에 안 남음(반대로 unique 위반은 중복 기록).
- 기타: `;run` 히스토리 상실(`No statement to execute.`), `;ex` 축약 경고 부재, `N command(s) successfully processed.` 간헐 누락, `;con <bad_user>` 에러 순서, timezone checksum 클라이언트 메시지 부재.

#### D. SHARD — 41건 (의도된 제거)
- `_08_shard` 36/37 + 기타 5: `config error, shard1, SHARD is not supported` / `failed to initialize proxy shared memory`(broker_config.c:1322, #116 D2). `_40_guava/cbrd_26401`도 SHARD 의존. → TC 스위트 제외 처리(제외 목록에 `_08_shard` 전체).

#### E. 서버측 SQL/메시지 차이 — 21건 (PRODUCT 다수)
- **트리거 `EXECUTE PRINT` 출력 없음**: `bug_bts_17026`(5케이스 전부 0줄), `bug_bts_11918` — print 액션이 서버 스레드에서 실행되며 클라이언트 stdout으로 안 돌아옴. PRODUCT(설계 결정 필요).
- **`block_ddl_statement`/`block_nowhere_statement` 미적용**: `itrack_1002718`, `_02_user_authorization` — 클라이언트측 파라미터 검사가 서버로 옮겨지면서 빠짐. PRODUCT.
- **`SET SYSTEM PARAMETERS` 세션 지속 안 됨**: `bug_bts_9098`(intl_date_lang 등 GET에 미반영). PRODUCT.
- **XASL 캐시/plandump 텍스트**: `cbrd_20149_*` 4건 `sql user text` 후행 `;` + 빈 줄 추가·순서 변경, `bug_bts_12920` `sql hash text`에 접속 파라미터 직렬화 문자열 노출, `bug_bts_9491/9771` plan dump에 `Statistics updated successfully` 줄 추가/순서. PRODUCT(출력 호환).
- 기타: `bug_3427` CCI `cci_cursor_update` 미반영, `bug_bts_13276` 결과 3행 초과 fetch, `bug_bts_7625` `;set access_ip_control=y` 에러, `bug_bts_10665` 서버 .err의 SQL_ID 태그 부재, `cbrd_24396` ignore-index 힌트 시맨틱 에러 미발생, `cbrd_24563` 잘못된 `regexp_engine` 값 미거부.

#### F. 행/타임아웃 — 17건 (+노드 hang 2건은 A 참조)
- **`_10_plcsql/isolation_commit_rollback/_01_read_committed/test01~17` 11건 동일 시그니처(PRODUCT 의심)**: 세션 3이 PL/CSQL 프로시저(`CALL test_commit_rollback('commit')`)로 커밋한 뒤 세션 4의 단순 `SELECT`가 `Timeout waiting for marker 'N rows'`로 영원히 안 돌아옴(READ COMMITTED에서 락 대기 없어야 함). 서버 내 PL 세션이 커밋 후 락/래치를 쥔 채 남거나 세션 4 wire가 멈춘 것으로 보임.
- `bug_bts_7462_2`(lock_timeout=-1 시나리오 hang, 1205s), `bug_bts_8041`(1388s), `bug_bts_4697`(40스레드 JDBC `Request timed out`), `cbrd_23633`/`cbrd_23722`(java 프록시→서버 포트 13091 패턴 hang), `bug_bts_13376`(lazy 1000 커넥션 중 960 예외 + 1205s → G에도 해당).

#### G. 접속 경로(adoption) — 13건 (에러코드·메시지 호환성)
- 존재하지 않는 DB/서버 다운 시 에러가 바뀜: JDBC `-353 → -21112`(`bug_bts_10721`), CCI `-677 'Failed to connect to database server' → -20004 'Cannot communicate with server'`(`bug_bts_10234`), csql `Failed to connect… → cannot connect to the server adoption socket (is the server running?)`(`bug_bts_10073`, `bug_bts_5095`, `_03_api_01` ko_KR/en_US 메시지), 긴 사용자명이 클라이언트에서 선차단되지 않음(`bug_bts_8649`).
- 대량 전송/부하 직후 접속 불가: `bug_bts_6290`(120MB BLOB insert 중 `Cannot communicate with the broker`), `bug_bts_9692`(JDBC 배치 데드락 스트레스 직후 csql adoption 실패), `bigdata_alltype_test`(loaddb 16384 objects 직후 `server connection error`), `bug_bts_9585`(브로커 경유 query cancel 타임아웃), `cbrd_25868`(PL/CSQL kill-mid-transaction 후 롤백 미반영 117~120행 잔존), `bug_bts_9010`(`aborted by the system due to server failure` 메시지 부재).

#### H. 크래시 — 코어 18개 / 8 TC (PRODUCT)
| 시그니처 | TC | 코어 | 비고 |
|---|---|---|---|
| **cub_server `xqmgr_execute_query` (query_manager.c:1635) ← `qmgr_execute_query`(network_interface_cl.c:7797) ← `execute_query`(query_cl.c:127) ← `do_execute_prepared_subquery`(execute_statement.c:15653) ← `db_compile_statement_local`(db_vdb.c:950)** | `_39_fig_cake/cbrd_25035`, `_39_fig_cake/cbrd_25395/cte`, `_39_fig_cake/cbrd_25395/uncorrelated` | 3 | 동일 스택 3회 = **결정적**. 서버 스레드에서 컴파일 중 uncorrelated 서브쿼리/CTE를 즉시 실행하는 client-side 경로가 in-server로 폴드되며 `xqmgr_execute_query`에 잘못된 컨텍스트(thread_p/query cache)로 진입하는 것으로 보임 |
| cub_manager `er_clear` → `cuberr::context::get_thread_local_context` assert (error_context.cpp:342) | `_06_issues/_25_2h/cbrd_26247` | 2 | B와 같은 뿌리(직결 CS 클라이언트의 TLS error context 미초기화) |
| TC 바이너리 `active_query` SIGSEGV `db_query_end_internal` (db_query.c:3653) | `_05_addition/bug_cubridsus2023` | 1 | B 참조 |
| TC 바이너리 `1_test` 자체 assert (1_test.c:55) | `_30_banana_qa/issue_13845_kill/_01_test_by_cci` | 2 | CCI 장기 질의 kill 시 기대 rc 불일치 → 제품 동작 차이 가능 |
| **cub_server 코어, 스택 미해독** — analyzer가 메인스레드 `epoll_wait`(master_connector.cpp:440)만 출력하고 `fullstack.<pid>`가 0바이트, 또는 8프레임 전부 `?? ()` | `_06_issues/_12_2h/bug_bts_8303`(2), `_06_issues/_15_1h/bug_bts_14565`(1+1), `_10_plcsql/cbrd_25668`(1+1), `issue_13845_kill/_01_test_by_cci`(1+1) | 8 | 공통점: **클라이언트를 도중에 kill(SIGKILL java/csql/CCI)하거나 csql 300회 연타(bug_bts_14565)** 중 서버 사망. n42 서버 .err에는 크래시 직전 `Dynamic loader already initialized (-380)`가 driver_session마다 반복됨(cbrd_25668, PL). **로그로는 스레드 특정 불가 → 코어 gdb 분석 필요**(아티팩트 tar에 코어 포함, 각 200MB+) |
| fault-injection `Assertion 'fault injection: random exit' failed` (worker_pool `execute_current_task`) | `_06_issues/_15_2h/bug_bts_17534` | 2 | TC가 `fault_injection_test=recovery`로 유도한 random exit. TC는 `fi_handler_random_exit`를 제외 처리하지만 CTP 코어 스캐너가 NOK 처리. 업스트림 develop에서 이 TC가 통과하는지 확인 필요(미정) |

#### I~L
- **I PL/CSQL·JavaSP 3**: `cbrd_25072_func`(owners-rights 트리거 메시지 부재), `_12_javasp/case_caution_01`(재귀 16단계 `sp_sum(16)` 결과 136 부재), `cbrd_23846_CS`(중첩 SP 에러 `Stored procedure execute error:` 반복 횟수 상이).
- **J HA 1**: `bug_bts_13351` cci_applier가 `Apply SQL log: FAILED` 후 자기 종료 안 함.
- **K 환경 1**: `_04_misc/_05_query_cache/itrack_10011` 테스트 디렉터리에 잔존 `testdb_vinf` → createdb 실패 후 연쇄.
- **L 미분류 16**: 콘솔 출력이 캡처되지 않아 판단 불가 5건(`bug_bts_5452`, `cbrd_27064`, `cbrd_27075`, `cbrd_20654`, `bug_bts_14288`), CDC 파생 2건(`cbrd_24910`, `cbrd_26911` 재접속), `cbrd_24335`(synonym DDL trail 로그 0줄), `cbrd_26410`(SLOW_QUERY 로그 블록 부재), `cbrd_25452`(vacuumdb --dump/plandump tmp 파일 미생성), `_01_normal_test`(cubrid.conf 우선순위 케이스가 실패해야 하는데 접속 성공), `param_ansi_quotes`, `_01_basic_test_04`(regexp 배치 출력 중간 절단), `bug_bts_9611/9593/9617/10511/11841`.

### 4. 다음 CI 전 권고 (결정 아님, 정리)
1. **즉시 제외**: hang 2건(`bug_bts_7558`, `bug_bts_4321_2`) + `_08_shard` 전체 — 이것만으로 미실행 105건이 살아나고 41+2건이 빠짐.
2. **제품 수정 우선순위**: H(`xqmgr_execute_query` 결정적 크래시 3, 미해독 cub_server 코어 8 → 코어 gdb), B(CDC/직결 CS 접속 단일 근인 64+), F-plcsql isolation hang 11, E(trigger print / block_ddl / SET SYSTEM PARAMETERS 세션), C(`;plan detail`).
3. **결정 필요(제품 vs TC)**: histogram 세션커맨드 존치, `driver_session` 프로그램명 노출, 접속 실패 에러코드(-21112/-20004) 호환, `Statistics updated successfully`류 클라이언트 메시지 복원.

원자료: CircleCI tests API 전건 + 50노드 `test_local.log`/`test-shell.xml` + ERROR_BACKUP readme/fullstack을 `.git_ignored_dir/scratch/ci7837/`에 보존(테스트별 분류 jsonl 포함). 부록(테스트별 표, 미실행 105건 목록)은 아래 코멘트.

===== 2026-09-02T05:38:46Z https://github.com/xmilex-git/workspace/issues/176#issuecomment-5504979823
**부록 1/2 — NOK 372건 테스트별 분류표 (A~D)** — 로그 근거 1차 분류. 신뢰도 low는 재검토 필요.
<summary><b>A. CAS 프로세스 모델 가정</b> — 129건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_01_utility/_11_killtran/itrack_10002` | 36 | killtran output has no 'cub_cas' program name so TC's kill-by-username loop never triggers | Tran index ... Program name | high |
| `_01_utility/_38_csql/_enhance_csql03` | 14 | csql --sysadm self-kill (;k / ;k 1 / ;res) sequence no longer produces the expected 1 ERROR line | + csql -udba csql03 --sysadm | medium |
| `_01_utility/_38_csql/csql_kill` | 35 | csql ';k' self/other-session kill semantics differ without separate CAS process | csql_kill-1 : NOK | low |
| `_01_utility/_40_broker/_enhance_b1` | 48 | broker per-CAS sql_log file never created (no cub_cas process to write it) | cat: '/home/CUBRID/log/broker/sql_log/broker1_*.sql.log': No such file or directory | high |
| `_01_utility/_40_broker/_enhance_b3` | 46 | broker per-CAS sql_log file never created; broker_log_top/broker_log_converter operate on missing file | broker_log_top -t '/home/CUBRID/log/broker/sql_log/*.sql.log' | high |
| `_01_utility/_40_broker/_enhance_b4` | 13 | broker_log_top operates on non-existent CAS sql_log glob; downstream log_top.q/log_top.t files never produced | No such file or directory[/home/CUBRID/log/broker/sql_log/*.sql.log] | high |
| `_01_utility/_40_broker/_enhance_b6` | 22 | broker_changer sql_log rejected with explicit direct-handoff message; sql_log file never exists | Cannot change sql_log on a direct-handoff broker; CAS execution parameters are server parameters (cas_*) | high |
| `_01_utility/_40_broker/broker` | 21 | cubrid_broker add/drop/restart <broker> rejected with 'is a direct-handoff front (no CAS pool)'; broker_log_top on nonexistent CAS sql.log | Cannot add appl server: broker [query_editor] is a direct-handoff front (no CAS pool) | high |
| `_01_utility/_40_broker/broker_runner` | 44 | broker_log_top/broker_log_converter/broker_log_runner operate on nonexistent per-CAS sql.log | broker_log_top -F1 1 -T '12 31' -q sql_info_bad.txt /home/CUBRID/log/broker/sql_log/broker1_1.sql.log | high |
| `_05_addition/broker_10001` | 0 | broker per-CAS sql_log file (testbroker_1.sql.log) never created | cp: cannot stat '/home/CUBRID/log/broker/sql_log/testbroker_1.sql.log': No such file or directory | high |
| `_05_addition/broker_10002` | 12 | broker per-CAS sql_log file never created (same mechanism as broker_10001) | cp: cannot stat '/home/CUBRID/log/broker/sql_log/testbroker_1.sql.log': No such file or directory | high |
| `_05_addition/bug_xdbms_sus1333` | 48 | broker per-CAS sql_log file (testbroker_1.sql.log) never created; '*** elapsed time' never logged | grep: /home/CUBRID/log/broker/sql_log/testbroker_1.sql.log: No such file or directory | high |
| `_05_addition/bug_xdbms_sus1431` | 21 | per-broker sql_log files (broker1_1..5.sql.log) receive no 'select' entries — CAS-side query logging removed | cat .../broker1_1.sql.log .../broker1_2.sql.log ... \| grep -c select | high |
| `_05_addition/bug_xdbms_sus1545` | 42 | 'cubrid broker status -f' no longer reports any CLIENT rows (no CAS pool to enumerate) | ++ grep CLIENT | high |
| `_05_addition/bug_xdbms_sus1937` | 37 | 'cubrid broker status' output format/line-count differs from the recorded answer (extra 'HANDOFFS' column, no per-CAS rows) | diff record.txt result failed | high |
| `_05_addition/bug_xdbms_sus1964` | 1 | broker error_log directory never created ($CUBRID/log/broker/error_log/*.err missing) though JDBC driver itself reports 'Has been interrupte | cubrid.jdbc.driver.CUBRIDException: Has been interrupted.[CAS INFO-127.0.0.1:13091,1,1],... | high |
| `_06_issues/_10_1h/bug_3734` | 3 | SIGKILL of a --no-auto-commit csql client mid multi-statement transaction: expected 'Unknown class dba.t1' (rollback of the uncommitted CREA | kill -9 57200 (csql client killed mid create-table/create-index/.../drop-table batch) | medium |
| `_06_issues/_11_1h/bug_bts_4321_1` | 15 | test greps 'ps -f' for 'broker1_cub_cas_N' process names to get per-CAS pids for broker_changer/broker status -f checks; those processes no  | pid1=`ps -u $USER -f \| grep broker1_cub_cas_1 \| grep -v grep \| awk '{print $2}'` | high |
| `_06_issues/_11_2h/bug_bts_5423` | 23 | case 6 paramdump diff: actual server parameter list has 3 new/extra entries not in the saved answer -- '[S] ddl_audit_log_size', '[S] cas_sq | diff bug_bts_5423.answer bug_bts_5423.log failed | high |
| `_06_issues/_11_2h/bug_bts_5783` | 12 | broker_changer SLOW_LOG / SLOW_LOG_DIR rejected with 'Cannot change SLOW_LOG on a direct-handoff broker; CAS execution parameters are server | Cannot change SLOW_LOG on a direct-handoff broker; CAS execution parameters are server parameters (cas_*) | high |
| `_06_issues/_11_2h/bug_bts_6199` | 6 | 'cubrid broker status -f' never shows IDLE/BUSY connection-state columns for a long-running query (no per-CAS state to report) | cat t1 \| grep IDLE -> empty; cat t2 \| grep BUSY -> empty | high |
| `_06_issues/_11_2h/bug_bts_6327` | 24 | broker per-CAS sql_log file never created; 'end_tran ROLLBACK' expected line absent | cat: '/home/CUBRID/log/broker/sql_log/*.sql.log': No such file or directory | high |
| `_06_issues/_11_2h/bug_bts_6347` | 23 | 'cubrid broker status -b -f' no longer has per-CAS '*' rows with a numeric request-count column 16 to sum | awk '/\*/{total=total+$16;}END {print total}' -> total=0 (expected 2) | high |
| `_06_issues/_12_1h/bug_bts_6364` | 38 | broker per-CAS sql_log file never created; 'query_cancel client ip ... port' line never logged | cat: '/home/CUBRID/log/broker/sql_log/*.log': No such file or directory | high |
| `_06_issues/_12_1h/bug_bts_6779` | 14 | 'cubrid broker status' output has no per-CAS IDLE/CLOSE status entries to count | idle=0 (expidle expected < idle) | high |
| `_06_issues/_12_1h/bug_bts_6910` | 45 | per-CAS unix domain sockets ($CUBRID/var/CUBRID_SOCK/broker1.1..5) are never created (no CAS pool) | ls /home/CUBRID/var/CUBRID_SOCK \| grep 'broker1.$i' -> cnt_broker=0 for each i=1..5 | high |
| `_06_issues/_12_2h/bug_bts_10045` | 3 | broker_changer APPL_SERVER_MAX_SIZE_HARD_LIMIT change reports unexpected 'fail' outcomes (8 instead of 0) even before the deliberately-inval | result=8 (from test_change_broker_info_APPL_SERVER_MAX_SIZE_HARD_LIMIT.sh testing broker_changer APPL_SERVER_M | high |
| `_06_issues/_12_2h/bug_bts_10260` | 30 | broker_changer APPL_SERVER_MAX_SIZE_HARD_LIMIT no longer produces the 'must be between 1 and 2097151' validation message for an out-of-range | broker_changer query_editor APPL_SERVER_MAX_SIZE_HARD_LIMIT 10485760 | high |
| `_06_issues/_12_2h/bug_bts_7549` | 12 | broker per-CAS sql_log file (broker1*.log) never created under a MIN/MAX_NUM_APPL_SERVER=5 config | rm: cannot remove '/home/CUBRID/log/broker/sql_log/*': No such file or directory | high |
| `_06_issues/_12_2h/bug_bts_7657` | 32 | broker per-CAS sql_log file never created; 'close_req_handle' CCI logging line never appears | grep: /home/CUBRID/log/broker/sql_log/*.log: No such file or directory | high |
| `_06_issues/_12_2h/bug_bts_7666` | 9 | broker per-CAS sql_log/error_log files never created ('prepare srv_h_id error:-494', 'was not found', 'COMMUNICATION ERROR net_read_header', | grep: /home/CUBRID/log/broker/sql_log/*.log: No such file or directory | high |
| `_06_issues/_12_2h/bug_bts_7956` | 24 | expects a JDBC queryTimeout parameter (':?queryTimeout=60001') recorded in the per-CAS sql_log; log file/content absent | resultcount=`grep ':?queryTimeout=60001' $CUBRID/log/broker/sql_log/broker1_1.sql.log \| wc -l` | high |
| `_06_issues/_12_2h/bug_bts_8237` | 38 | broker_log_converter fails to open the (nonexistent) per-CAS sql_log ('fopen error'), so broker_log_runner replay never runs | fopen error[/home/CUBRID/log/broker/sql_log/broker1_1.sql.log] | high |
| `_06_issues/_12_2h/bug_bts_8351` | 30 | broker/server log files are not recreated after deletion under sustained concurrent load: 'log File is not exist' fires 10000 times (r2), an | r1,r2,r3,r4 = 1,10000,1,1  (expected 0,0,2,>=1) | medium |
| `_06_issues/_12_2h/bug_bts_8611` | 41 | broker_log_converter fails to open the (nonexistent) per-CAS sql_log ('fopen error'), same mechanism as bug_bts_8237 | fopen error[/home/CUBRID/log/broker/sql_log/broker1_1.sql.log] | high |
| `_06_issues/_12_2h/bug_bts_8907` | 12 | a CCI client reconnecting after a mid-session 'cubrid server stop/start' gets 'cci_prepare fail: -20004' instead of the expected retryable ' | cci_prepare fail: -20004 | medium |
| `_06_issues/_12_2h/bug_bts_8973` | 36 | same recurring '-20004' CCI reconnect error after mid-session server restart as bug_bts_8907 (test explicitly asserts 20004 must NOT appear) | result.txt\|grep 20004 -> nonzero (expected 0) | medium |
| `_06_issues/_12_2h/bug_bts_9478` | 34 | 'cubrid broker status' never shows the expected number of per-CAS CLOSE_WAIT rows | cat broker.log \| grep CLOSE_WAIT \| wc -l -- looped waiting for 10, never satisfied | high |
| `_06_issues/_12_2h/bug_bts_9602_1` | 15 | 'cubrid broker status' no longer prints the per-CAS 'ID PID QPS PSIZE STATUS' table header/columns | grep 'ID.* PID.* QPS.* PSIZE.* STATUS' result1.log -> not found | high |
| `_06_issues/_12_2h/bug_bts_9602_3` | 28 | 'cubrid broker status' never shows the per-CAS CLOSE_WAIT state after a client is killed (same family as bug_bts_9478/bug_bts_6199) | grep 'CLOSE_WAIT' result1.log -- condition not satisfied | high |
| `_06_issues/_13_1h/bug_bts_10181` | 47 | broker per-CAS sql_log file never created; 'CAS MEMORY USAGE ... HAS EXCEEDED MAX SIZE' never logged | grep: /home/CUBRID/log/broker/sql_log/*.log: No such file or directory | high |
| `_06_issues/_13_1h/bug_bts_10235` | 46 | 'cubrid broker status -f -b' has no 'broker1' row/columns to parse for total/wait CAS counts under MIN/MAX_NUM_APPL_SERVER config | grep broker1 a.log \| awk '{print $6}' -> total_count=0 | high |
| `_06_issues/_13_1h/bug_bts_10502` | 13 | JDBC connection to a stored-procedure-enabled db fails outright with 'Attempt to use a not supported service' instead of completing the Main | cubrid.jdbc.driver.CUBRIDException: jdbc:cubrid:localhost:130... Attempt to use a not supported service | high |
| `_06_issues/_13_1h/bug_bts_10503` | 47 | same 'Attempt to use a not supported service' JDBC failure as bug_bts_10502 (shared Main/DbTest/StressSchemaHelper functional-suite test fam | cubrid.jdbc.driver.CUBRIDException: jdbc:cubrid:localhost:130... / Attempt to use a not supported service \| H | high |
| `_06_issues/_13_1h/bug_bts_10505` | 46 | same 'Attempt to use a not supported service' JDBC failure family (Main/DbTest test suite) | cubrid.jdbc.driver.CUBRIDException: jdbc:cubrid:localhost:130.../ Attempt to use a not supported service | high |
| `_06_issues/_13_1h/bug_bts_10507` | 13 | same 'Attempt to use a not supported service' JDBC failure family (Main/DbTest test suite) | cubrid.jdbc.driver.CUBRIDException ... \| Here (twice, at two different points in the session) | high |
| `_06_issues/_13_1h/bug_bts_10509` | 45 | same 'Attempt to use a not supported service' JDBC failure family (Main/DbTest test suite) | cubrid.jdbc.driver.CUBRIDException: jdbc:cubrid:localhost:130.../ Attempt to use a not supported service \| He | high |
| `_06_issues/_13_1h/bug_bts_10519` | 22 | same 'Attempt to use a not supported service' JDBC failure family (Main/DbTest test suite) | cubrid.jdbc.driver.CUBRIDException ... \| Here (twice) | high |
| `_06_issues/_13_1h/bug_bts_10521` | 41 | same shared JDBC functional-suite Main test used by bug_bts_10502/10503/10505/10507/10509/10519 comes back empty for the 'Holdable results m | grep 'Holdable results may not be updatable or sensitive' record.txt -> result=0 (expected 3) | medium |
| `_06_issues/_13_1h/bug_bts_10765` | 18 | broker per-CAS sql_log files never created; a JDBC query never gets logged | grep: /home/CUBRID/log/broker/sql_log/broker*.log: No such file or directory | high |
| `_06_issues/_13_1h/bug_bts_10773` | 3 | broker error_log directory never created; 'A database has not been restarted' message expected during a mid-session server restart never app | cp: cannot stat '/home/CUBRID/log/broker/error_log/*.err': No such file or directory | high |
| `_06_issues/_13_1h/bug_bts_11524` | 16 | cubrid broker status -f column 14 (client CAS version) empty/missing | client_version=`cat result.log\| grep 'CLOSE_WAIT' \| awk '{print $14}'` | high |
| `_06_issues/_13_1h/bug_bts_9655` | 40 | tranlist_invalid diff + 'Unknown class' drop message includes stale CAS INFO tag | diff tranlist_invalid.log tranlist_invalid.answer failed | medium |
| `_06_issues/_13_2h/bug_bts_12148` | 36 | charSet=euckr connection param no longer resolves en_US/ksc-euc locale combination | Locales for language 'en_US' are not available with charset 'ksc-euc'. select to_days(...)[CAS INFO-localhost: | medium |
| `_06_issues/_14_1h/bug_bts_10046` | 47 | broker admin_change_conf on APPL_SERVER_MAX_SIZE now rejected as a server-side (cas_*) parameter | Cannot change APPL_SERVER_MAX_SIZE on a direct-handoff broker; CAS execution parameters are server parameters  | high |
| `_06_issues/_14_1h/bug_bts_10047` | 48 | broker changeconf on SQL_LOG_MAX_SIZE/LONG_QUERY_TIME/LONG_TRANSACTION_TIME/TIME_TO_KILL/SQL_LOG2 all rejected as server-side (cas_*) params | Cannot change SQL_LOG_MAX_SIZE on a direct-handoff broker; CAS execution parameters are server parameters (cas | high |
| `_06_issues/_14_1h/bug_bts_11649` | 10 | broker changeconf on LONG_QUERY_TIME/LONG_TRANSACTION_TIME rejected as server-side (cas_*) params | Cannot change LONG_QUERY_TIME on a direct-handoff broker; CAS execution parameters are server parameters (cas_ | high |
| `_06_issues/_14_1h/bug_bts_12558` | 30 | broker sql_log directory/file layout missing: 'connect db' entries never captured | cat: '/home/CUBRID/log/broker/sql_log/*.sql.log': No such file or directory | high |
| `_06_issues/_14_1h/bug_bts_13339` | 0 | 'show access status' loses per-session client HOSTNAME/program ('csql') identity for all connected users | <   'DBA'                 NULL                           NULL                  NULL | high |
| `_06_issues/_14_1h/bug_bts_13357` | 40 | csql interactive ';.h on' (communication histogram) feature unsupported: 'Histogram commands are not supported by this csql' | Histogram commands are not supported by this csql. | high |
| `_06_issues/_14_1h/bug_bts_13390` | 18 | every JDBC operation fails (SQLException) when test forces AS-pool reuse via MIN_NUM_APPL_SERVER=1 + repeated reconnect between ops | change_broker_parameter MIN_NUM_APPL_SERVER=1 | medium |
| `_06_issues/_14_1h/bug_bts_13392` | 37 | 'show access status' missing HOSTNAME/csql identity AND session intl_date_lang/intl_number_lang/intl_collation come back empty | <   'DBA'                 NULL                           NULL                  NULL | high |
| `_06_issues/_14_1h/bug_bts_13567` | 8 | cubrid_replay depends on non-existent broker sql_log file | cubrid_replay -I localhost -P 13091 -u dba -d db13567 /home/CUBRID/log/broker/sql_log/broker1_1.sql.log out | high |
| `_06_issues/_14_2h/bug_bts_13265` | 23 | 'cubrid broker status' never reports a CLOSE_WAIT connection state, cascading into a 'cannot connect to database' failure | bug_bts_13265-1 : NOK broker do not in CLOSE_WAIT status | high |
| `_06_issues/_14_2h/bug_bts_13994/err_log_dir` | 22 | broker error_log directory/files missing: '/home/CUBRID/log/broker/error_log/broker1*.err: No such file or directory' | grep: /home/CUBRID/log/broker/error_log/broker1*.err: No such file or directory | high |
| `_06_issues/_14_2h/bug_bts_13994/max_prepared_stmt_count` | 21 | broker changeconf on MAX_PREPARED_STMT_COUNT rejected as a server-side (cas_*) parameter | Cannot change MAX_PREPARED_STMT_COUNT on a direct-handoff broker; CAS execution parameters are server paramete | high |
| `_06_issues/_14_2h/bug_bts_13994/session_timeout` | 44 | broker changeconf on SESSION_TIMEOUT rejected as a server-side (cas_*) parameter | Cannot change SESSION_TIMEOUT on a direct-handoff broker; CAS execution parameters are server parameters (cas_ | high |
| `_06_issues/_14_2h/bug_bts_14649` | 3 | broker sql_log/query_editor sql_log files missing, driving Count=0 both places | cp: cannot stat '/home/CUBRID/log/broker/sql_log/broker1_1.sql.log': No such file or directory | high |
| `_06_issues/_14_2h/bug_bts_15093` | 32 | broker sql_log directory/file missing: cp/grep of broker1_1.sql.log fails ('No such file or directory') | cp /home/CUBRID/log/broker/sql_log/broker1_1.sql.log . | high |
| `_06_issues/_15_1h/bug_bts_14752` | 26 | cubrid statdump missing a 'WORKER,PAGE' statistics section | ++ egrep -i WORKER,PAGE cubrid_statdump.log | medium |
| `_06_issues/_15_2h/bug_bts_17595_2` | 42 | old bundled JDBC driver jar (JDBC-9.3.0.0206) cannot connect at all against the merged server | Exception in creating the connection : cubrid.jdbc.driver.CUBRIDException: Attempt to use a not supported serv | high |
| `_06_issues/_17_1h/cbrd_20145_1` | 22 | communication_histogram=yes debug stats (';plan'/';lock'/histogram dumps, 'Histogram of client requests') no longer produced by thin csql | Histogram of client requests:  (present only in answer, absent from actual output) | medium |
| `_06_issues/_17_1h/cbrd_20759/hide_cubrid_replay` | 16 | cubrid_replay tool: broker SQL log file not found / cci connect error, so replay produces no output where a masked-password line was expecte | cannot open input file '/home/CUBRID/log/broker/sql_log/broker1_1.sql.log' | medium |
| `_06_issues/_18_1h/bug_bts_13845` | 38 | 'kill <tranid>' / 'kill query' / 'kill transaction' csql statements no longer interrupt the target session (all 14 sub-cases NOK) | + csql -u dba qadb -c 'kill 1;' | high |
| `_06_issues/_18_1h/bug_bts_14303` | 3 | killquery.sql / 'kill' statement doesn't interrupt a long-running 'select sleep(300)' session; no '1 transaction killed' confirmation | + csql -u dba qadb -i killquery.sql | high |
| `_06_issues/_18_1h/bug_bts_14305` | 37 | same 'kill <tranid>' failure signature as bug_bts_13845/14303 - target session not aborted, no '1 transaction killed' message | + csql -u bb qadb -c 'kill 1;' | high |
| `_06_issues/_20_1h/cbrd_23613_1` | 20 | 'cubrid broker start/stop' now fails outright for a DIRECT_HANDOFF+SSL config unless a new DIRECT_HANDOFF_SSL_DB parameter is set, breaking  | config error, broker1, DIRECT_HANDOFF with SSL requires DIRECT_HANDOFF_SSL_DB | high |
| `_06_issues/_20_1h/cbrd_23613_5` | 42 | identical DIRECT_HANDOFF_SSL_DB broker-start failure as cbrd_23613_1 | config error, query_editor, DIRECT_HANDOFF with SSL requires DIRECT_HANDOFF_SSL_DB | high |
| `_06_issues/_20_2h/cbrd_23688_1` | 39 | identical DIRECT_HANDOFF_SSL_DB broker-start failure blocking all 3 sub-cases | config error, query_editor, DIRECT_HANDOFF with SSL requires DIRECT_HANDOFF_SSL_DB | high |
| `_06_issues/_20_2h/cbrd_23688_4` | 38 | same DIRECT_HANDOFF_SSL_DB broker-start failure | config error, query_editor, DIRECT_HANDOFF with SSL requires DIRECT_HANDOFF_SSL_DB | high |
| `_06_issues/_20_2h/cbrd_23688_5` | 3 | same DIRECT_HANDOFF_SSL_DB broker-start failure | config error, query_editor, DIRECT_HANDOFF with SSL requires DIRECT_HANDOFF_SSL_DB | high |
| `_06_issues/_21_1h/cbrd_23860` | 28 | 'cubrid broker changer' (live parameter change) for SQL_LOG_MAX_SIZE reports no 'OK' and the value never actually updates from 100 to 200 | ++ broker_changer query_editor SQL_LOG_MAX_SIZE 200 | medium |
| `_06_issues/_21_1h/cbrd_23915` | 16 | broker SQL log directory/file is empty (no *.sql.log written), so a grep-for-bind-count check that expects specific line counts finds nothin | grep: /home/CUBRID/log/broker/sql_log/*.sql.log: No such file or directory | high |
| `_06_issues/_21_1h/cbrd_23991` | 48 | test tries to kill the CAS process by name ('xkill cub_cas') to force-close a holdable cursor's session; no cub_cas process exists so nothin | + xkill cub_cas | high |
| `_06_issues/_22_2h/cbrd_24517` | 15 | broker_log_top tool can't find the broker sql_log file at all ('No such file or directory'), same missing sql_log signature as cbrd_23915/cb | broker_log_top -F ... -T ... '/home/CUBRID/log/broker/sql_log/*.sql.log' | high |
| `_06_issues/_23_1h/cbrd_24644` | 47 | num_tran_rollbacks statistic is inflated by exactly the number of separate short-lived 'csql -c' single-statement connections (40 extra roll | "num_tran_rollbacks" : "120",   \|   "num_tran_rollbacks" : "80", | high |
| `_06_issues/_23_2h/cbrd_24679` | 12 | broker sql_log file broker1_1.sql.log does not exist | grep: /home/CUBRID/log/broker/sql_log/broker1_1.sql.log: No such file or directory | high |
| `_06_issues/_24_1h/cbrd_25337` | 6 | ddl_audit log file csql_<db>_ddl.log never created; later 'cannot connect to the broker' | grep: /home/CUBRID/log/ddl_audit/csql_db25337_1_ddl.log: No such file or directory | medium |
| `_06_issues/_24_2h/cbrd_25078` | 24 | db_user.last_access_time/host/program (show access status / login() method) stays NULL after connect | 'A'   NULL   NULL   \|   'A'   ??:??:??.???  ??/??/????   'HOSTNAME' | medium |
| `_06_issues/_24_2h/cbrd_25209` | 47 | ddl_audit log $CUBRID/log/ddl_audit/broker1_*.log missing DDL/end_tran/ABORT entries | awk '-F\|' '{print $7}' $CUBRID/log/ddl_audit/broker1_*.log > $2.log | high |
| `_06_issues/_24_2h/cbrd_25233` | 48 | ddl_audit log $CUBRID/log/ddl_audit/broker1_1_ddl.log (per-CAS-slot file) missing content | awk '-F\|' '{print $6,$7}' $CUBRID/log/ddl_audit/broker1_1_ddl.log > autocommit_true.log | high |
| `_06_issues/_24_2h/cbrd_25511` | 41 | CM getlogfileinfo returns 0 log file paths for broker1 (previously listed per-CAS sql/error logs) | curl -k -X POST https://.../cm_api -d '{"task":"getlogfileinfo", "broker":"broker1", ...}' | high |
| `_06_issues/_24_2h/cbrd_25654` | 38 | ddl_audit log now named per-database (db<name>_1_ddl.log) instead of per-broker, breaking a glob-based grep -c check | grep -ic '\|db25654_2\|...' /home/CUBRID/log/ddl_audit/db25654_1_1_ddl.log /home/CUBRID/log/ddl_audit/db25654_ | high |
| `_06_issues/_25_1h/cbrd_26038` | 28 | broker_log_converter input file $CUBRID/log/broker/sql_log/broker1_1.sql.log missing, causing 'Cannot find proper file' and duplicated resul | broker_log_converter $CUBRID/log/broker/sql_log/broker1_1.sql.log ./brk1.in | medium |
| `_06_issues/_26_1h/cbrd_26745` | 17 | TC explicitly checks for a CAS process (broker1_cub_cas) that no longer exists | cbrd_26745-1 : NOK CAS process (broker1_cub_cas) did not start | high |
| `_07_index_enhancement/_04_topn_prepare_stmt` | 24 | xasl_debug_dump '<reset:...>' plan-reset debug markers never appear in csql client output | set system parameters 'xasl_debug_dump=yes'; | medium |
| `_07_index_enhancement/_05_topn_limit_external_sort` | 23 | same xasl_debug_dump '<reset:...>' marker missing pattern as _04_topn_prepare_stmt | + cnt=0 | medium |
| `_11_codecoverage/system_parameter/broker_file` | 20 | TC counts `ps ux \| grep cub_cas` processes against MIN/MAX_NUM_APPL_SERVER-derived expected counts; always 0 | ps ux \| grep cub_cas \| grep -v grep \| wc -l | high |
| `_28_features_844/issue_10676_caserror` | 45 | broker sql_log files broker1_1.sql.log / broker1_1.slow.log missing, so JDBC connect-error audit trail (error codes -171/-165) is entirely a | grep jdbc:cubrid: /home/CUBRID/log/broker/sql_log/broker1_1.sql.log -> No such file or directory | high |
| `_28_features_844/issue_10986_eventlog/_01_eventlog_slowquery` | 33 | slow-query server event log missing the 'sql: ...' line for a query that should be logged as a slow query | diff result.log result.answer: 0a1 > sql: select [dba.x].[a], [dba.x].[b] from [dba.x] [dba.x] where ... group | medium |
| `_28_features_844/issue_10986_eventlog/_03_eventlog_tempvolume` | 32 | EXTEND_VOLUME_INFO event-log entries (with client/sql/time/pages fields) missing from expand.txt | diff expand.txt_temp_diff expand.answer_temp_diff: 8a9,15 > // ::. - EXTEND_VOLUME_INFO ... client: ... sql: i | medium |
| `_28_features_844/issue_11202_temp_volume_create` | 31 | same EXTEND_VOLUME_INFO missing-entry pattern as _03_eventlog_tempvolume | diff create.log create.answer: > // ::. - EXTEND_VOLUME_INFO ... client: ... sql: insert into [dba.x] ... | medium |
| `_29_features_920/issue_10952_set_names/_03_session_persistence` | 24 | broker status 'OFF' appl-server count polling never converges from 2 to 1 (CAS on/off status semantics no longer apply); very long runtime ( | cubrid broker status \| grep OFF \| wc -l -> cnt=2 repeatedly, loop condition '[' 2 -eq 1 ']' never satisfied  | medium |
| `_30_banana_qa/issue_14036_show_job_queue/_03_killtran` | 19 | test.sh loops killtran using awk-parsed column 1 of 'cubrid tranlist' output to find ACTIVE tran index; loop never terminates, causing a 20- | cubrid tranlist ${dbname}>>tran ... awk '{print $1}' trantmp ... cubrid killtran -i ${tran_index} -f $dbname | medium |
| `_30_banana_qa/issue_14038_show_threads/_01_basic` | 12 | hardcoded 'show threads' total/worker thread counts off by a fixed delta (218 vs expected 217, 205 vs expected 204) due to new server-side w | threads_total=218 | high |
| `_30_banana_qa/issue_14038_show_threads/_02_extend_03` | 41 | same show-threads hardcoded thread-count family as _01_basic (multiple NOK cases at start of run) | _02_extend_03-1 : NOK | medium |
| `_30_banana_qa/issue_14039_show_tran_tables/_01_basic` | 40 | 'show transaction tables' Client_program column now reports 'driver_session' instead of 'csql' for a csql client transaction | <         Client_program          : 'csql' | high |
| `_30_banana_qa/issue_14039_show_tran_tables/_02_extend_01` | 11 | same Client_program='driver_session' vs 'csql' mismatch as _01_basic | _02_extend_01-1 : NOK | medium |
| `_30_banana_qa/issue_14039_show_tran_tables/_02_extend_02` | 10 | same Client_program='driver_session' vs 'csql' mismatch as _01_basic | _02_extend_02-1 : NOK | medium |
| `_35_cherry/cbrd_22705_online_index_parallel/_03_check_index_normal` | 39 | test explicitly sets broker MIN_NUM_APPL_SERVER/MAX_NUM_APPL_SERVER=100 to control CAS concurrency for an online-index race test; java clien | + change_broker_parameter MIN_NUM_APPL_SERVER=100 | medium |
| `_35_cherry/issue_21654_server_side_loaddb/loaddb_CS/_06_issues/_11_2h/bug_bts_5784` | 27 | prepare-error message's trailing '[CAS INFO-127.0.0.1:13091,1,N]' connection-slot id differs from the recorded answer (2 vs 1); rest of the  | < prepare error: -493, ... [CAS INFO-127.0.0.1:13091,1,2]. | medium |
| `_35_cherry/issue_22015_QEWC/big_data_1` | 46 | QEWC (Query Executed With Commit) check greps server .err log for 'stran_server_auto_commit_or_abort: transaction committed.' after each JDB | Test FAIL: insert into t1 values(1, 'aaa'), ... | high |
| `_35_cherry/issue_22015_QEWC/big_data_2` | 13 | same missing 'stran_server_auto_commit_or_abort: transaction committed.' log message as big_data_1 | > Test FAIL: insert into t1 values(1, 'aaa'),(2,'bbb'),(3,'ccc' | high |
| `_35_cherry/issue_22015_QEWC/cci_api` | 45 | same missing 'stran_server_auto_commit_or_abort: transaction committed.' log lines drive multiple Test Fail entries across execute/prepare_a | stran_server_auto_commit_or_abort: transaction committed.     < | high |
| `_35_cherry/issue_22015_QEWC/cci_ds` | 22 | same missing autocommit-notice log lines as cci_api (27 occurrences of the marker string found only on the expected/answer side) | cci_ds-1 : NOK | high |
| `_35_cherry/issue_22015_QEWC/cci_holdability` | 36 | same missing autocommit-notice log lines pattern (12 occurrences on expected side) | cci_holdability-1 : NOK | medium |
| `_35_cherry/issue_22015_QEWC/error_test_1` | 21 | checkQEWC(true, sql) fails for a select-after-error case; underlying cause is the same missing commit-notice log marker (0 occurrences anywh | Test PASS -> Test FAIL: select * from t1 order by 1; | medium |
| `_35_cherry/issue_22015_QEWC/error_test_2` | 44 | same QEWC commit-notice-log-missing family as error_test_1 | error_test_2-1 : NOK | medium |
| `_35_cherry/issue_22015_QEWC/holdability_1` | 5 | same QEWC commit-notice-log-missing family | holdability_1-1 : NOK | medium |
| `_35_cherry/issue_22015_QEWC/holdability_2` | 20 | same QEWC commit-notice-log-missing family | holdability_2-1 : NOK | medium |
| `_35_cherry/issue_22015_QEWC/jdbc_dbcp` | 42 | same QEWC commit-notice-log-missing family (DBCP pooled connections) | jdbc_dbcp-1 : NOK | medium |
| `_35_cherry/issue_22015_QEWC/operation_type` | 0 | same QEWC commit-notice-log-missing family, 18 occurrences of the marker found only on the expected side across many cases | operation_type-1..5 : NOK | high |
| `_36_damson/cbrd_23726/castest` | 46 | ddl_audit log files (broker1_1_ddl.log, per-broker/per-CAS-slot naming) are empty/absent, so 'DDL SUCCESS'-style checks fail; test also time | mv '/home/CUBRID/log/ddl_audit/*.log' ./test2_ddl.log | high |
| `_36_damson/cbrd_23726/csqltest` | 13 | ddl_audit log format changed ('elapsed time N.NNN auto_commit' lines missing, replaced by bare 'auto_commit <STATEMENT>' lines) and one file | < elapsed time 0.003 auto_commit | high |
| `_37_elderberry/apis_869_jdbc_property` | 21 | test greps the per-CAS broker sql log (broker1_1.sql.log) for each JDBC URL property; the file no longer exists, so every property check fai | grep: /home/CUBRID/log/broker/sql_log/broker1_1.sql.log: No such file or directory | high |
| `_37_elderberry/apis_877` | 44 | same missing per-CAS broker sql log file (broker1_1.sql.log) as apis_869_jdbc_property | cp: cannot stat '/home/CUBRID/log/broker/sql_log/broker1_1.sql.log': No such file or directory | high |
| `_38_fig/cbrd_24416` | 33 | broker sql_log/error_log directories no longer exist | grep: /home/CUBRID/log/broker/sql_log/*.slow.log: No such file or directory | high |
| `_39_fig_cake/cbrd_24438` | 11 | broker password-masked SQL/slow log completely absent | diff pwd_exam_sql.log pwd_exam_sql.answer failed | high |
| `_39_fig_cake/cbrd_25295` | 17 | test greps `ps` for a cub_cas process name that no longer exists | ++ ps -u root -f | high |

</details>

<details><summary><b>B. 직결 CS 클라이언트/CDC API</b> — 64건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_03_itrack/itrack_1001685` | 48 | direct CS-mode db_restart() (libcubridcs, bypasses broker) fails with bare 'error db_restart()', no further diagnostic text captured in log | cubrid server start: success | low |
| `_05_addition/bug_cubridsus2023` | 41 | direct CS-mode client 'active_query' segfaults in db_query_end_internal (src/compat/db_query.c:3653) | bug_cubridsus2023.sh: line 39: 6842 Segmentation fault (core dumped) ./active_query | medium |
| `_06_issues/_11_1h/bug_bts_5097` | 46 | direct CS-mode client 'obj' (libcubridcs, db_restart("applylogdb",0,"foo")) produces zero stdout at all (insert1.log/select1.log fully empty | gcc -g -o obj obj.c -I/home/CUBRID/include -L/home/CUBRID/lib -lcubridcs | low |
| `_06_issues/_25_2h/cbrd_26247` | 47 | cub_manager (CM) aborts in cuberr::context::get_thread_local_context during db_restart/boot_restart_client, from a client CM REST call | PROCESS NAME: [cub_manager] | high |
| `_37_elderberry/cbrd_23842_cdc/api/api01` | 32 | CDC client library cubrid_log_connect_server() fails to connect to the server (grep SUCCESS in api01.log finds 0 matches); same failure shap | + ./api01 10.233.104.55 1568 api01db | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api02` | 9 | same CDC connect-failure family as api01 (grep-based SUCCESS check against api02.log fails) | api02-1 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api04` | 4 | same CDC connect-failure family as api01 | api04-1/2/3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api05` | 8 | same CDC connect-failure family as api01 | api05-2/3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api06` | 16 | same CDC connect-failure family as api01 | api06-1/2 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api11` | 15 | same CDC connect-failure family as api01 | api11-1/3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api13` | 28 | same CDC connect-failure family as api01 | api13-1 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api18` | 24 | same CDC connect-failure family as api01 | api18-2 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api21` | 48 | same CDC connect-failure family as api01 | api21-1 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api23` | 46 | same CDC connect-failure family as api01 | api23-3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api24` | 13 | same CDC connect-failure family as api01 | api24-1/2/3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api25` | 45 | same CDC connect-failure family as api01 | api25-3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api26` | 22 | same CDC connect-failure family as api01 | api26-3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/api/api30` | 5 | same CDC connect-failure family as api01 | api30-3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_26993` | 20 | same CDC connect-failure family as api01 | cbrd_26993-1/2 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27022` | 18 | explicit rc=-10 (CUBRID_LOG_FAILED_CONNECT) reported directly by the test; bug's actual scenario (connect/find_lsa) could never be exercised | cbrd_27022-1 : NOK case1: environment issue - 0 successful runs out of 300 attempts (connect/find_lsa kept fai | high |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27024` | 0 | explicit CASE1_CONNECT_RC=-10, same CDC connect-failure family | CASE1_CONNECT_RC=-10 | high |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27025` | 12 | test validates that invalid ports (0, -1, 65536) are rejected (pass) but the valid-port connect case itself fails, i.e. even a well-formed c | cbrd_27025-1/2/3 : OK  port_0_rejected / port_neg1_rejected / port_65536_rejected | high |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27027` | 41 | test expects distinct rc codes for bad-host/bad-dbname/no-port/bad-password cases, but all 4 cases uniformly return rc=-10 (generic connect  | CASE1_BAD_HOST_RC=-10 | medium |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27064` | ? | log is essentially empty (only header, no console output captured) — cannot determine cause | TEST: .../cbrd_27064.sh | low |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27075` | ? | log is essentially empty (only header, no console output captured) — cannot determine cause | TEST: .../cbrd_27075.sh | low |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27077` | 10 | same CDC connect-failure family, rc=-10 explicit in both cases; test also reports server_alive=1 new_cores=0 (server itself stayed up, no cr | cbrd_27077-1 : NOK case1: insert= update= update_len= server_alive=1 new_cores=0 : connect rc=-10 | high |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27081` | 18 | explicit '[API ERROR] cubrid_log_connect_server' printed by the test binary itself for all 3 MVCC-overflow-update regression cases | [API ERROR] cubrid_log_connect_server | high |
| `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27083` | 39 | same CDC connect-failure family; every failing case's message ends in 'connect rc=-10', explicitly shown by the test itself (51 occurrences) | cbrd_27083-1 : NOK case1: expected exit=0 rc=-8, got exit=10: connect rc=-10 | high |
| `_37_elderberry/cbrd_23842_cdc/ddl/index/index01` | 38 | same CDC connect-failure family; 'DDL SUCCESS' marker never appears in index01.log because the extractor never connects | ./index01 10.233.111.36 1568 index01db 1788287599 | medium |
| `_37_elderberry/cbrd_23842_cdc/ddl/procedure/procedure01` | 3 | same CDC connect-failure family as index01 (all cases NOK from the start) | procedure01-1/2/3/4/5 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/ddl/serial/serial01` | 37 | same CDC connect-failure family as index01 | serial01-1/2/3/4/5 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/ddl/serial/serial02` | 36 | same CDC connect-failure family as index01 | serial02-1/2/3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/ddl/serial/serial03` | 1 | same CDC connect-failure family as index01 | serial03-1/2/3 : NOK | medium |
| `_37_elderberry/cbrd_23842_cdc/ddl/serial/serial04` | 17 | same CDC connect-failure family as index01 | serial04 : NOK (see fails/324_.. pattern) | low |
| `_37_elderberry/cbrd_23842_cdc/ddl/table/table01` | 35 | same CDC connect-failure family as index01 | table01 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/ddl/table/table02` | 34 | same CDC connect-failure family as index01 | table02 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/ddl/trigger/trigger01` | 33 | same CDC connect-failure family as index01 | trigger01 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/ddl/view/view01` | 32 | same CDC connect-failure family as index01 | view01 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/ddl/view/view02` | 9 | same CDC connect-failure family as index01 | view02 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/ddl/view/view03` | 31 | same CDC connect-failure family as index01 | view03 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/delete/delete01` | 4 | same CDC connect-failure family as index01, applied to DELETE DML capture | delete01 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/delete/delete02` | 8 | same CDC connect-failure family as delete01 | delete02 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/delete/delete03` | 16 | same CDC connect-failure family as delete01 | delete03 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/delete/delete04` | 30 | same CDC connect-failure family as delete01 | delete04 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/delete/delete06` | 6 | same CDC connect-failure family as delete01 | delete06 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/delete/delete07` | 15 | same CDC connect-failure family as delete01 | delete07 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/insert/insert02` | 28 | same CDC connect-failure family, applied to INSERT DML capture | insert02 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/insert/insert03` | 27 | same CDC connect-failure family as insert02 | insert03 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/insert/insert04` | 14 | same CDC connect-failure family as insert02 | insert04 : NOK | low |
| `_37_elderberry/cbrd_23842_cdc/dml/update/update01` | 26 | CDC C-client log always empty across all cases | + ./update01 10.233.104.14 1568 cbrd23842 0 | medium |
| `_37_elderberry/cbrd_23842_cdc/dml/update/update02` | 25 | CDC C-client log always empty across all cases | + '[' 0 -eq 1000 ']' | medium |
| `_37_elderberry/cbrd_23842_cdc/dml/update/update03` | 24 | CDC C-client log always empty across all cases | + '[' 0 -eq 1000 ']' | medium |
| `_37_elderberry/cbrd_23842_cdc/dml/update/update04` | 23 | CDC C-client log always empty across all cases | + '[' 0 -eq 1000 ']' | medium |
| `_37_elderberry/cbrd_23842_cdc/dml/update/update05` | 47 | CDC C-client log always empty across all cases | + '[' 0 -eq 1000 ']' | medium |
| `_37_elderberry/cbrd_23842_cdc/dml/update/update06` | 48 | CDC C-client log always empty across all cases | + '[' 0 -eq 1000 ']' | medium |
| `_37_elderberry/cbrd_23842_cdc/dml/update/update08` | 46 | CDC C-client log always empty across all cases | + '[' 0 -eq 1000 ']' | medium |
| `_37_elderberry/cbrd_23842_cdc/operate/oper01` | 13 | CDC operate API test: expected API-error string absent from result.log | ++ grep '\[API ERROR\] cubrid_log_set_all_in_cond' result.log | low |
| `_37_elderberry/cbrd_23842_cdc/operate/oper02` | 45 | CDC operate API test: expected API-error string absent from result.log | + write_nok | low |
| `_37_elderberry/cbrd_23842_cdc/operate/oper03` | 22 | CDC operate API test failures (4 cases) | + write_nok | low |
| `_37_elderberry/cbrd_23842_cdc/operate/oper04` | 21 | CDC operate API test failures | + write_nok | low |
| `_37_elderberry/cbrd_23842_cdc/operate/oper05` | 44 | CDC operate API test failures | + write_nok | low |
| `_37_elderberry/cbrd_23842_cdc/operate/oper06` | 5 | CDC operate API test failures | + write_nok | low |
| `_37_elderberry/cbrd_23842_cdc/operate/oper07` | 20 | CDC operate test expects 100 ERRORs and 0 successes, got 0 and 0 (client produced no output at all) | ++ grep -c 'DML SUCCESS' result.log | low |
| `_37_elderberry/cbrd_23842_cdc/thread` | 33 | CDC multithreaded client test failures (4 of 5 sub-cases) | ++ grep -c 'API ERROR' result2.log | low |

</details>

<details><summary><b>C. thin csql 동작 차이</b> — 58건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_01_utility/_01_sqlx/bug_cubridsus2018` | 48 | ';run' session command loses statement history ('ERROR: No statement to execute.') | 1 row selected. (0.006000 sec) Committed. (0.000000 sec) | medium |
| `_01_utility/_14_lockdb/itrack_10001` | 30 | 'SET TRANSACTION ISOLATION LEVEL' no longer prints the 'Isolation level set to: X' confirmation line | diff tt.out itrack_10001.out failed | medium |
| `_01_utility/_38_csql/csql_hist` | 38 | communication histogram session commands (;.h on / ;xr / ;.x) not functional in thin csql | csql_hist-1 : NOK | medium |
| `_01_utility/_38_csql/csql_hist_01` | 37 | communication histogram session commands (;.h on / ;xr / ;.x) not functional in thin csql | csql_hist_01-1 : NOK | medium |
| `_01_utility/_38_csql/csql_history` | 36 | csql statement-history session command (;run/;history family) behavior differs in thin client | csql_history-1 : NOK | low |
| `_04_misc/_05_query_cache/itrack_10001` | 23 | 'Histogram commands are not supported by this csql.' — ;.h on/;xr/;.x no-ops, Num_data_page_fetches never printed | csql> ;.h on | high |
| `_04_misc/_05_query_cache/itrack_10002` | 47 | ';.h on' silently a no-op in non-interactive (heredoc) csql; no Num_data_page_fetches ever printed | page1= (empty) | high |
| `_04_misc/_05_query_cache/itrack_10003` | 48 | 'Histogram commands are not supported by this csql.' (multiple occurrences) | Histogram commands are not supported by this csql. (x4) | high |
| `_04_misc/_05_query_cache/itrack_10006` | 46 | 'Histogram commands are not supported by this csql.' | Histogram commands are not supported by this csql. (x4) | high |
| `_04_misc/_05_query_cache/itrack_10007` | 13 | 'Histogram commands are not supported by this csql.' | Histogram commands are not supported by this csql. (x2) | high |
| `_04_misc/_05_query_cache/itrack_10008` | 45 | 'Histogram commands are not supported by this csql.' | Histogram commands are not supported by this csql. (x2) | high |
| `_04_misc/_05_query_cache/itrack_10009` | 22 | 'Histogram commands are not supported by this csql.' | Histogram commands are not supported by this csql. (x2) | high |
| `_04_misc/_05_query_cache/itrack_10010` | 21 | 'Histogram commands are not supported by this csql.' (multiple) | Histogram commands are not supported by this csql. (x8) | high |
| `_04_misc/_05_query_cache/itrack_10018` | 42 | 'Histogram commands are not supported by this csql.' | Histogram commands are not supported by this csql. (x2) | high |
| `_05_addition/bug_xdbms802` | 30 | csql histogram no longer emits 'Histogram is allowed only for DBA' for a non-DBA user | ++ grep 'Histogram is allowed only for DBA' record.txt | high |
| `_05_addition/bug_xdbms_sus1420` | 22 | csql histogram no longer prints 'SERVER EXECUTION STATISTICS' block | ++ grep 'SERVER EXECUTION STATISTICS' record.txt | high |
| `_05_addition/bug_xdbms_sus1660` | 0 | csql histogram error-reporting ('ER' lines) not produced for a large cross-join query, likely because histogram itself is disabled | expect PrintHist.exp dba testdb 'select * from db_class a, db_class b limit 1000' > record.txt | medium |
| `_05_addition/bug_xdbms_sus1955` | 36 | csql.err client-side error log file gets no 'WARNING' entry even though the error is printed to stdout normally | ERROR: before ' ;' / Unknown class "public.noexistclass". | medium |
| `_06_issues/_10_1h/bug_2796` | 45 | ';plan detail' session command produces no query-plan/dump text in the thin csql (PrintInfo.exp mechanism) | expect PrintInfo.exp dba $db 'select 1;' >ppp.log | high |
| `_06_issues/_11_1h/bug_bts_1305` | 45 | ';plan detail' produces no Join graph / Query plan output at all (PrintInfo.exp), so downstream 'N command(s) successfully processed.' marke | diff bug_1305_result bug_1305_answer failed / all 'Join graph segments...Query plan...' lines only on the answ | high |
| `_06_issues/_11_1h/bug_bts_1484` | 5 | ';plan detail' produces no Join graph / Query plan output (same PrintInfo.exp mechanism as bug_bts_1305) | diff bug_1484_result bug_1484_answer failed | high |
| `_06_issues/_11_1h/bug_bts_2166` | 20 | ';plan detail' produces no Join graph / Query plan output (same PrintInfo.exp mechanism) | diff bug_2166_result bug_2166_answer failed | high |
| `_06_issues/_11_1h/bug_bts_2562` | 42 | case 2 (data.result vs data.expect, the actual SELECT result rows captured from the same ';plan detail' PrintInfo.exp session) diverges — li | bug_bts_2562-2 : NOK | medium |
| `_06_issues/_11_1h/bug_bts_351` | 40 | ';plan detail' produces no Join graph / Query plan output (same PrintInfo.exp mechanism) | diff bug_351_result bug_351_answer failed | high |
| `_06_issues/_11_1h/bug_bts_4033` | 32 | ';plan detail' PrintInfo.exp session never reaches the '10 command(s) successfully processed.' marker so the '3 rows selected' count check f | endLine computed from grep '10 command(s) successfully processed.' on the .log — same PrintInfo.exp/;plan deta | medium |
| `_06_issues/_11_1h/bug_bts_4059` | 9 | ';plan detail' produces no Join graph / Query plan output (same PrintInfo.exp mechanism) | diff plan.result plan.expect failed | high |
| `_06_issues/_11_1h/bug_bts_4083` | 31 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_4083_result bug_4083_answer failed | high |
| `_06_issues/_11_1h/bug_bts_430` | 6 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_430_result.tmp bug_430_answer.tmp failed | high |
| `_06_issues/_11_1h/bug_bts_443` | 25 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_443_result bug_443_answer failed | high |
| `_06_issues/_11_1h/bug_bts_4470` | 10 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_4470_1_result bug_4470_1_answer failed | high |
| `_06_issues/_11_1h/bug_bts_4671` | 12 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_4671_result bug_4671_answer failed | high |
| `_06_issues/_11_1h/bug_bts_4704` | 10 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_4704_result bug_4704_answer failed | high |
| `_06_issues/_11_1h/bug_bts_4826` | 35 | PrintInfo.exp/';plan detail' session's captured SELECT result rows (CONNECT BY hierarchical query) missing entirely from actual output | diff bug_4826_result bug_4826_answer failed | medium |
| `_06_issues/_11_1h/bug_bts_4835` | 33 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_4835_result.tmp bug_4835_answer.tmp failed | high |
| `_06_issues/_11_1h/bug_bts_4900` | 31 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_4900_result.tmp bug_4900_answer.tmp failed | high |
| `_06_issues/_11_1h/bug_bts_825` | 28 | ';plan detail' produces no Join graph / Query plan output (PrintInfo.exp mechanism) | diff bug_825_result bug_825_answer failed | high |
| `_06_issues/_11_1h/bug_xdbms4268` | 14 | csql ';x' execute-and-continue session command intermittently omits the '<N> command(s) successfully processed.' tally line (LOB/autocommit- | result2='9a10,11\n> 4 command(s) successfully processed.\n...\n> 0 command(s) successfully processed....' | medium |
| `_06_issues/_12_1h/bug_bts_6159` | 20 | expected 'skipping' warning for the ';ex' (ambiguous/short) session command no longer appears | expect exec_sql.exp sends 'select ...;select ...;' then ';ex\r' | low |
| `_06_issues/_13_1h/bug_bts_10055` | 36 | interactive csql session ending with ';ex' no longer prints the '<N> command(s) successfully processed.' tally line (9 of 9 interactive case | diff result1.result result1.answer: 2a3,4 > (blank) > 1 command(s) successfully processed. | high |
| `_06_issues/_13_2h/bug_bts_11351` | 30 | cubrid plandump 'sql user text' entries now include trailing semicolon and differ in ordering | <     sql user text = insert into foo select i+4, j, c from foo; | medium |
| `_06_issues/_13_2h/bug_bts_12253` | 33 | server-shutdown-during-session disconnect message not written to csql.err | r1=`grep "connected to database server" a.log` | medium |
| `_06_issues/_14_1h/bug_bts_13430` | 3 | csql `;ge intl_date_lang` / `;ge intl_number_lang` / `;ge intl_collation` session commands return empty instead of resolved defaults | < intl_date_lang="" | high |
| `_06_issues/_14_1h/bug_bts_14023` | 44 | unique-constraint error message now duplicated into csql.err when TC expects it absent there | + cat csql.err | medium |
| `_06_issues/_15_1h/bug_bts_11092` | 22 | csql batch-file output missing '1 command(s) successfully processed.' completion messages | diff csql1.linux answer3 failed | medium |
| `_06_issues/_15_1h/bug_bts_14229` | 3 | invalid isolation-level error text ('invalid_level is not defined') not written to csql.err | invalid_level is not defined. | medium |
| `_06_issues/_15_1h/bug_bts_16933` | 39 | 'SET autocommit off' invalid-system-parameter error text not written to csql.err | ERROR: invalid set system parameter | high |
| `_06_issues/_15_2h/bug_bts_16113` | 25 | 'Isolation level set to:' / level-name confirmation lines missing entirely from csql session-command output (3 cases) | 0a1,6 | high |
| `_06_issues/_18_1h/cbrd_22118/01_general` | 17 | 'update statistics ... on column' no longer prints the 'Statistics updated successfully: N table, M column(s).' confirmation line | 230a231 / 231a233 | high |
| `_06_issues/_20_2h/cbrd_23732` | 31 | same 'Statistics updated successfully: 1 table, 2 columns.' confirmation message missing as in cbrd_22118/01_general | diff test.log test.answer failed | high |
| `_06_issues/_21_1h/cbrd_23850` | 6 | session command output for isolation level ('Isolation level set to: / REPEATABLE READ') missing from csql output | diff select.log select.answer failed | medium |
| `_06_issues/_21_1h/cbrd_23879` | 14 | same 'Statistics updated successfully: 4 tables, 8 columns.' confirmation message missing | diff test.log test.answer failed | high |
| `_06_issues/_21_2h/cbrd_23956` | 22 | expected 'ERROR CODE = -550' annotation (for a MERGE 'multiple rows match' error) is missing from csql.err; grep count is 0 instead of 2 | ERROR: Multiple rows in source table match the same row in destination table. | medium |
| `_06_issues/_23_1h/cbrd_24668` | 48 | same 'Statistics updated successfully: 1 table, 2 columns.' confirmation message missing | diff test1.log test1.answer failed | high |
| `_06_issues/_24_2h/cbrd_24407` | 25 | lock_timeout session parameter always reports -1 instead of the set value | lock_timeout=-1                          \|    lock_timeout=0 msec | medium |
| `_06_issues/_25_1h/cbrd_25932` | 30 | ';con <invalid_user>' error ordering/text differs: extra blank+immediate error, generic 'No error message available' where a specific messag | < ERROR: User "usr1" is invalid. | high |
| `_30_banana_qa/issue_14187_timezone_compatibility/01_server_db_compatibility` | 27 | expected client-side message 'Incompatible timezone data: csql has different checksum from server' no longer appears in csql.log/csql.err | + csql -udba before -c 'select * from db_root' | medium |
| `_32_features_930/issue_12508_show_slotted_page/_01_show_slotted_page_header/_02_basic_check` | 22 | expected SQL error text ('Cannot find the page...', 'Argument page is missing') is printed to stdout but not captured into csql.err, which t | + cat csql.err \| grep 'Cannot find the page 1000 of volume 0' -> r1=1 (not found) | medium |
| `_38_fig/cbrd_24563/_01_basic_test_04` | 16 | csql regexp character-class compile-error message has an extra trailing quote/space | < ERROR: before '  regexp '[[.exclamation-mark.]]'); ' | medium |

</details>

===== 2026-09-02T05:38:48Z https://github.com/xmilex-git/workspace/issues/176#issuecomment-5504980131
**부록 2/2 — 테스트별 분류표 (E~L) + 미실행 105건**

<details><summary><b>D. SHARD 제거</b> — 41건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_06_issues/_13_2h/bug_bts_12003` | 10 | broker refuses to start/stop with shard config: 'config error, shard1, SHARD is not supported' | config error, shard1, SHARD is not supported | high |
| `_06_issues/_14_1h/bug_bts_11650` | 18 | broker start fails: 'config error, shard1, SHARD is not supported' | config error, shard1, SHARD is not supported | high |
| `_06_issues/_14_1h/bug_bts_11932` | 37 | shard-hinted SQL script (/*+ shard_id(0) */) produces no output at all vs full expected transcript | > ======================================= SQL 1 =========================================== | high |
| `_06_issues/_14_1h/bug_bts_12953` | 1 | SHARD_KEY-hinted prepare/execute script produces no output vs expected 'Prepare SQL'/'execute N - a' transcript | > Prepare SQL : select a from t1 where a >= /*+ SHARD_KEY */ 0 | high |
| `_08_shard/_02_cubrid_broker01` | 48 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_04_shard_connection` | 46 | config error, shard1, SHARD is not supported (broker start fails for all shard sub-cases) | config error, shard1, SHARD is not supported \| failed to metadata validate check [shard1] | high |
| `_08_shard/_05_shard_key` | 13 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_06_user_hash_function` | 45 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_07_shard_hint` | 22 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_08_err_handling01` | 21 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_09_err_handling02` | 44 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_10_err_handling03` | 5 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_11_err_handling04` | 20 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_13_shard_command` | 42 | config error, shard1, SHARD is not supported \| cubrid_broker: invalid option -- '1' | config error, shard1, SHARD is not supported | high |
| `_08_shard/_16_shard_log_level` | 0 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_18_shard_err_log` | 12 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10041` | 41 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10125` | 40 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10130` | 11 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10218` | 10 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10390` | 18 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10441` | 39 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10792` | 38 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10823` | 3 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_10837` | 37 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_11271` | 36 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_11290` | 1 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_11570/bug_bts_11570` | 17 | config error, shard1, SHARD is not supported \| failed to connect database. [shard1] | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_11570/bug_bts_11899` | 35 | config error, shard1, SHARD is not supported \| failed to connect database. [shard1] | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_11977` | 34 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_12054` | 33 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_12073` | 32 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_12088` | 9 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_12094` | 31 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_12115` | 4 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_12321` | 8 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_7156/bug_bts_11174` | 16 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_7156/bug_bts_7156` | 30 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_8839` | 6 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_08_shard/_50_cubridsus/bug_bts_9956` | 15 | config error, shard1, SHARD is not supported | config error, shard1, SHARD is not supported | high |
| `_40_guava/cbrd_26401/26401_01` | 22 | JDBC shard client fails to connect and throws NullPointerException instead of completing | < Cannot connect to a broker[CAS INFO-localhost:14091,0,0],[SESSION-0],[URL-jdbc:cubrid:localhost:14091:db2640 | medium |

</details>

<details><summary><b>E. 서버측 SQL/메시지 차이</b> — 21건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_03_itrack/itrack_1002718` | 18 | block_ddl_statement / block_nowhere_statement parameters no longer block the statement (expected ERROR, got 'Execute OK') | + csql tdb -C --no-single-line -i itrack_1002718.sql2 | high |
| `_06_issues/_10_1h/bug_3427` | 41 | CCI cci_cursor_update() on an updatable holdable cursor reports success but the update is not persisted (select afterward shows the old valu | Prepare ok!(1) | medium |
| `_06_issues/_12_2h/bug_bts_7625` | 37 | csql ';set access_ip_control=y' now errors ('error: set access_ip_control=y') instead of succeeding | diff result1.log result.answer | medium |
| `_06_issues/_12_2h/bug_bts_9967` | 11 | 'update statistics on t1;' no longer prints the 'Statistics updated successfully: 1 table, 1 column.' confirmation message (same family as t | diff record.txt result failed | high |
| `_06_issues/_13_1h/bug_bts_9491` | 0 | plan-dump diff: extra/reordered 'Statistics updated successfully' and error-message ordering | > Statistics updated successfully: 1 table, 2 columns. | low |
| `_06_issues/_13_1h/bug_bts_9771` | 10 | insert-with-subquery plan dump has 2 extra 'Statistics updated successfully' lines vs answer | diff insert_with_subquery_level513.log insert_with_subquery_level513.answer failed | medium |
| `_06_issues/_13_2h/bug_bts_10665` | 17 | server .err log missing the SQL_ID-tagged 'Query execution error' line the TC greps for | ++ grep 'Query execution error. ERROR_CODE = -670, \/\* SQL_ID: .* \*\/ update t1 set a=1 where b=2' a.log | low |
| `_06_issues/_13_2h/bug_bts_11918` | 12 | trigger EXECUTE AFTER print action output missing once (out of 2 expected occurrences) | < call espinhd_tgr_upd | medium |
| `_06_issues/_14_1h/bug_bts_12920` | 37 | plandump 'sql hash text' now dumps full serialized connection-parameter string instead of plain SQL | <     sql hash text = select [dba.t0].[a] from [dba.t0] [dba.t0]?84=n;89=n;95=n;192=100;...;user= | medium |
| `_06_issues/_14_1h/bug_bts_13276` | 21 | Java and CCI clients both fetch 3 extra rows (6,7,8) beyond expected result set, before/after a server+broker restart | 6,8d5 | medium |
| `_06_issues/_15_1h/bug_bts_13852` | 11 | 'update statistics on all classes' missing 'Statistics updated successfully: N tables, M columns (K skipped: histogram type not supported)'  | diff result.log result.answer failed | medium |
| `_06_issues/_15_1h/bug_bts_17026` | 1 | BEFORE INSERT trigger 'execute print' action produces zero output across 5 cases (expected 6 'a' lines each) | 0a1,6 | high |
| `_06_issues/_15_1h/bug_bts_8682` | 6 | 'Statistics updated successfully:  table,  columns.' summary lines (with counts) missing from actual output | diff bug_8682.result bug_8682.expect failed | medium |
| `_06_issues/_17_1h/cbrd_20149_cache_clones` | 44 | XASL cache dump 'sql user text' now includes trailing ';' and an extra blank line vs. answer | sql user text = insert into tx values(1,1,1,1);   \|   sql user text = insert into tx values(1,1,1,1)  | high |
| `_06_issues/_17_1h/cbrd_20149_cache_work` | 5 | same as cbrd_20149_cache_clones: XASL cache 'sql user text' includes trailing ';' + extra blank line | sql user text = insert into tx values(1,1,1,1);   \|   sql user text = insert into tx values(1,1,1,1)  | high |
| `_06_issues/_17_1h/cbrd_20149_ddl` | 20 | same trailing-';' XASL cache text diff, plus cache entries appear in a different order than answer | sql user text = delete from tx where col1=30;   \|   sql user text = delete from tx where col1=30  | high |
| `_06_issues/_17_1h/cbrd_20149_recompile` | 42 | same trailing-';' XASL cache text diff as the other cbrd_20149 siblings | sql user text = INSERT INTO tx SELECT ROWNUM,ROWNUM,ROWNU...;   \|   ...(no trailing ;) | high |
| `_26_apricot_qa/_04_i18/general/_00_issues/bug_bts_9098` | 27 | SET SYSTEM PARAMETERS (intl_date_lang/intl_number_lang=en_US) not visible on a subsequent GET (session parameter not persisted) | diff log1.log_temp_diff result.answer_temp_diff: intl_date_lang="" (actual) vs intl_date_lang="en_US" (expecte | medium |
| `_29_features_920/issue_10952_set_names/_02_user_authorization` | 25 | many SET SYSTEM PARAMETERS values (add_column_update_hard_default, block_ddl_statement, intl_date_lang, string_max_size_bytes, etc.) revert  | add_column_update_hard_default=n (actual) \| add_column_update_hard_default=y (expected) | medium |
| `_38_fig/cbrd_24396` | 35 | ignore-index hint with two named indexes does not raise expected Semantic: error | ++ grep -rw Semantic: ./csql.err | low |
| `_38_fig/cbrd_24563/cbrd_24563` | 25 | invalid regexp_engine system-parameter value is not rejected at startup | > The 'regexp_engine' parameter at line xx in file '$CUBRID/con... | low |

</details>

<details><summary><b>F. 행/타임아웃</b> — 17건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_06_issues/_11_1h/bug_bts_4697` | 41 | JDBC 'Request timed out' exception under a 40-thread/20-iteration concurrent load test, expected clean 4-line output | cubrid.jdbc.driver.CUBRIDException: Request timed out. | medium |
| `_06_issues/_12_1h/bug_bts_8041` | 41 | test framework killed the run after >23 minutes (1388s, over the 10-minute CTP limit); test deliberately points databases.txt at an unreacha | RUNTIME: 1388.285 | medium |
| `_06_issues/_13_1h/bug_bts_10851` | 3 | OverflowBrokerJobQueue java client (testing MIN/MAX_NUM_APPL_SERVER=1 job-queue overflow behavior) runs the full 300s 'timeout' without comp | RUNTIME: 310.443 (script runs 'timeout 300 java OverflowBrokerJobQueue ...') | medium |
| `_06_issues/_15_1h/bug_bts_7462_2` | 30 | Test_7462_1 (lock_timeout=-1 scenario) hangs, harness kills the script after ~1205s | RUNTIME: 1205.12 | medium |
| `_06_issues/_20_1h/cbrd_23633` | 19 | test's single sub-case (a raw java proxy forwarding to port 13091, then a custom java client) eventually reports OK but the whole script tak |  : NOK timeout | medium |
| `_06_issues/_20_2h/cbrd_23722` | 34 | same java-proxy-to-server pattern as cbrd_23633: sub-case 1 passes quickly but the overall script hangs past the 10-minute CTP timeout with  |  : NOK timeout | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test01` | 18 | second concurrent csql session's SELECT never returns after first session commits via a stored procedure (READ COMMITTED visibility test) | send_sql 3 'CALL test_commit_rollback('\''commit'\'');' -> Marker 'OK' found | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test02` | 39 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '2 rows' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test03` | 38 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '5 rows' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test04` | 3 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '4 rows' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test05` | 37 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '1 row' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test08` | 17 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '6 rows' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test10` | 34 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '5 rows' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test13` | 9 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '5 rows' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test14` | 31 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '5 rows' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test15` | 4 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '1 row' | medium |
| `_10_plcsql/isolation_commit_rollback/_01_read_committed/test17` | 16 | same signature as test01: second session's SELECT after first session's stored-proc commit times out | Timeout waiting for marker '6 row' | medium |

</details>

<details><summary><b>G. 접속 경로(adoption)</b> — 13건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_06_issues/_11_1h/bug_bts_5095` | 48 | case 2 expects 'Failed to connect' in the JDBC exception message when connecting to a never-created database while server/broker are up; mes | grep 'Failed to connect' java1.log -> cnt=0 (case 1's analogous 'Cannot connect' check, run while service is f | low |
| `_06_issues/_11_2h/bug_bts_6290` | 14 | large (~120MB) BLOB insert via JDBC fails mid-transfer with 'Cannot communicate with the broker', row never persisted | cubrid.jdbc.driver.CUBRIDException: Cannot communicate with the broker[CAS INFO-localhost:13091,1,2],... | medium |
| `_06_issues/_12_1h/bug_bts_8649` | 10 | overly-long username is no longer rejected client-side before the connection attempt; now fails with the generic adoption-socket connect err | diff record.txt result failed | high |
| `_06_issues/_12_2h/bug_bts_9010` | 32 | expected client-side message 'Your transaction has been aborted by the system due to server failure or mode change' does not appear in csql  | grep '...aborted by the system due to server failure or mode change' log1.log -> 0 across 10 retries | medium |
| `_06_issues/_13_1h/bug_bts_10073` | 17 | connecting to an unknown database now returns the generic 'cannot connect to the server adoption socket' error instead of 'Failed to connect | < ERROR: Failed to connect to database server, 'unknown_db', on the following host(s): localhost | high |
| `_06_issues/_13_1h/bug_bts_10234` | 48 | CCI connect to a nonexistent database returns error -20004 'Cannot communicate with server' instead of the expected -677 'Failed to connect  | con error: -20004 / cci_error: -20004, Cannot communicate with server \|  con error: -20001 / cci_error: -677, | high |
| `_06_issues/_13_1h/bug_bts_10721` | 41 | JDBC connect error code changed from -353 to -21112 for scenario 1 (broker up, server/service down) | diff jdbc1.log jdbc.answer failed | high |
| `_06_issues/_13_1h/bug_bts_9585` | 12 | query cancel via broker times out; broker SQL log path missing | testQueryCancel : -20038 : Connection timed out | medium |
| `_06_issues/_13_1h/bug_bts_9692` | 11 | csql SELECT fails with 'cannot connect to the server adoption socket' right after a JDBC batch-deadlock stress test, though server is up | < ERROR: cannot connect to the server adoption socket (is the server running?) | medium |
| `_06_issues/_14_1h/bug_bts_13376` | 11 | opening 1000 lazy JDBC connections yields 960 exceptions; test also ran ~1205s (flagged NOK timeout) | ++ grep -c Exception test.result | medium |
| `_10_plcsql/bug_fix/cbrd_25868` | 48 | rows from a background PL/CSQL rollback/kill-mid-transaction case are NOT rolled back (extra rows 117-120 persist) | diff test_tran.log test_tran.answer: extra rows '117 1 aaa', '118 2 bbb', '119 3 ccc', '120 4 ddd' present in  | medium |
| `_24_apricot/_08_I18N/_02_msg_lang/_03_api_01` | 16 | localized (CUBRID_MSG_LANG=ko_KR/en_US) JDBC connect-failure message no longer matches expected 'host localhost' pattern in either language | grep '호스트 localhost에서' log1.log -> r1=0 | medium |
| `_35_cherry/issue_21654_server_side_loaddb/bigdata_alltype_test` | 28 | csql fails with 'ERROR: server connection error' immediately after a large cubrid loaddb (16384 objects) into two different databases | + csql -u dba -i tmp.sql dest_7811 | medium |

</details>

<details><summary><b>H. 크래시(코어)</b> — 8건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_06_issues/_12_2h/bug_bts_8303` | 9 | cub_server segfaults at startup inside the new master connector's epoll wait loop (cubconn::master::connector::run -> execute -> cubsocket:: | PROCESS NAME: [cub_server] | high |
| `_06_issues/_15_1h/bug_bts_14565` | 31 | core file found on host after test run (2 occurrences) |  : NOK found core file on host 10.233.104.3(/home/ERROR_BACKUP/AUTO_11.5.0.2738-7117c8a_20260902_031150) | high |
| `_06_issues/_15_2h/bug_bts_17534` | 5 | core file found on host after test run (2 occurrences) |  : NOK found core file on host 10.233.104.34(/home/ERROR_BACKUP/AUTO_11.5.0.2738-7117c8a_20260902_030654) | high |
| `_10_plcsql/cbrd_25668` | 42 | cub_server crashes at startup in cubsocket::epoll::wait / cubconn::master::connector::run during css_init (2 separate core dumps) | SUMMARY : [Core dumped in cubsocket::epoll::wait at src/base/epoll.cpp:56] | high |
| `_30_banana_qa/issue_13845_kill/_01_test_by_cci` | 20 | cub_server core dump in cubconn::master::connector::execute / cubsocket::epoll::wait during kill/timeout scenario | SUMMARY : [Core dumped in cubsocket::epoll::wait at src/base/epoll.cpp:56] | high |
| `_39_fig_cake/cbrd_25035` | 39 | cub_server core dump in xqmgr_execute_query | SUMMARY : [Core dumped in xqmgr_execute_query at src/query/query_manager.c:1635] | high |
| `_39_fig_cake/cbrd_25395/cte` | 9 | cub_server core dump in xqmgr_execute_query (same signature as cbrd_25035) | SUMMARY : [Core dumped in xqmgr_execute_query at src/query/query_manager.c:1635] | high |
| `_39_fig_cake/cbrd_25395/uncorrelated` | 31 | cub_server core dump in xqmgr_execute_query (same signature as cbrd_25035/cte) | SUMMARY : [Core dumped in xqmgr_execute_query at src/query/query_manager.c:1635] | high |

</details>

<details><summary><b>I. PL/CSQL·JavaSP</b> — 3건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_10_plcsql/cbrd_24731/plcsql_owners_rights/cbrd_25072_func` | 23 | expected 'There was an update on history table' trigger/DBMS_OUTPUT line missing from output (owners_rights function test) | diff test4.log test4.answer: 1a2 > There was an update on history table | low |
| `_12_javasp/case_caution_01` | 0 | recursive Java stored-procedure call sp_sum(16) does not produce expected sum 136 in csql output | csql -u dba caution_01 -c 'call sp_sum(16);' > test1.log | low |
| `_37_elderberry/cbrd_23846_javasp/cbrd_23846_CS` | 26 | nested stored-procedure recursion depth error message has different repetition count of 'Stored procedure execute error:' prefix | < ERROR: Stored procedure execute error: ... (16x) ... Too many nested stored procedure call. | medium |

</details>

<details><summary><b>J. HA</b> — 1건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_06_issues/_14_1h/bug_bts_13351` | 12 | cci_applier does not self-stop after a SQL apply failure ('cci_applier didn't stop, but we expect it stop') | bug_bts_13351-1 : NOK cci_applier didn't stop, but we expect it stop | medium |

</details>

<details><summary><b>K. 환경/플래키</b> — 1건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_04_misc/_05_query_cache/itrack_10011` | 44 | cubrid createdb failed: stale volume file 'testdb_vinf' already exists in the test case dir from a prior/leftover run, cascading into 'canno | Couldn't create database. | high |

</details>

<details><summary><b>L. 미분류</b> — 16건</summary>

| 테스트 | node | 시그니처 | 증거(발췌) | 신뢰도 |
|---|---|---|---|---|
| `_06_issues/_11_1h/bug_bts_5452` | ? | log file is essentially empty (only TEST/NODE/RUNTIME header, 'Test failed', no console output captured); node id itself is '?' | TEST: shell/_06_issues/_11_1h/bug_bts_5452/cases/bug_bts_5452.sh | low |
| `_06_issues/_12_2h/bug_bts_9611` | 14 | case 3 (Test_Multi.java, run after a 'cubrid broker start' with the broker already running) expects a 'CAS...SESSION...URL' pattern in a JDB | grep 'CAS.*SESSION.*URL' log3.log -> num3=0 (case 1's identical check on log1.log passed with num=1) | low |
| `_06_issues/_13_1h/bug_bts_9593` | 41 | multiple sub-case NOKs, no single clear diff isolated in time available | bug_bts_9593-2 : NOK | low |
| `_06_issues/_13_2h/bug_bts_11841` | 20 | CCI multi-thread test suite: 'COUNT: 0' occurs 2 times instead of expected 3 | ++ grep 'COUNT: 0' | low |
| `_06_issues/_13_2h/bug_bts_9617` | 23 | insufficient time to isolate case 2/3 failing diff | bug_bts_9617-2 : NOK | low |
| `_06_issues/_14_2h/bug_bts_10511` | 37 | 2 CUBRIDExceptions thrown loading bit-varying/BLOB data via JDBC; exact exception text not visible in captured log | ++ grep CUBRIDException | low |
| `_06_issues/_14_2h/bug_bts_14288` | 10 | not analyzed in time available | not inspected | low |
| `_06_issues/_17_1h/cbrd_20654` | 12 | error.log has content but the redirect/content is not visible in the captured console output | + csql -c 'select * from db_class a, db_class b, db_class c' db20654 | low |
| `_06_issues/_23_2h/cbrd_24910` | 10 | cubrid_log_connect_server/cubrid_log_find_lsa (CDC API) produced no SUCCESS and left no debug trace | ++ grep SUCCESS test.log | low |
| `_06_issues/_26_1h/cbrd_26911` | 31 | CDC client reconnection after abnormal termination (CBRD-26911 fix) regressed: both deterministic and kill-9 scenarios fail 100% | cbrd_26911-1 : NOK Client A failed to connect: RESULT=FAIL connect_server rc=-10 | medium |
| `_22_news_service_mysql_compatibility/_01_regular_expression/_01_basic_test_04` | 33 | regexp POSIX collating-element test output truncated/diverges partway through a long batch of queries | diff shows dozens of missing 'ERROR: ... Cannot compile regular expression: regex_error(error_collate)' lines  | low |
| `_23_mysql_compatibility/_01_config/param_ansi_quotes` | 30 | with compat_mode=cubrid, an ansi_quotes-dependent quoted-identifier CREATE/DROP TABLE sequence produces 0 successful commands instead of 2 ( | expect execute_in_csql.exp ';get ansi_quotes' 'create table t1(id int, "name" varchar(10))' ';x' 'drop table t | low |
| `_30_banana_qa/issue_10929_load_config_file/_01_normal_test` | 13 | cubrid.conf precedence tests (only db-conf, only local conf, CUBRID_CONF_FILE variants) now connect successfully where the TC expects them t | + csql -udba -c 'select count(*) from db_class;' db10929 | low |
| `_37_elderberry/cbrd_23845_synonym/cbrd_24335` | 14 | expected SQL/DDL trail log for synonym statements is completely empty (0 lines vs 19 expected) | 0a1,19 | medium |
| `_39_fig_cake/cbrd_25452` | 4 | admin dump utilities (vacuumdb --dump, plandump) did not create expected tmp dump files under $CUBRID/tmp | ++ grep -Ei 'vacuum_dump_\|qplan_dump_\|lock_dump_\|acl_dump_\|qcache_dump_\|logpb_dump_stat_\|logtb_dump_\|th | low |
| `_40_guava/cbrd_26410` | 5 | expected SLOW_QUERY log block and query-plan/statistics terms missing from server .err/.event logs | ++ grep -i -n -m 1 -E 'SLOW[_ ]QUERY' /home/CUBRID/log/server/cbrd26410_latest.event | low |

</details>
<details><summary><b>미실행 105건</b> — node 2(bug_bts_7558 hang 이후 50건) · node 29(bug_bts_4321_2 hang 이후 55건). 다음 CI에서 결과가 처음 나오는 테스트들</summary>

- `_40_guava/cbrd_26311/cbrd_26311_param`
- `_05_addition/bug_xdbms_sus884`
- `_06_issues/_11_2h/bug_bts_5784`
- `_06_issues/_12_2h/bug_bts_7558`
- `_06_issues/_12_2h/bug_bts_8140`
- `_06_issues/_12_2h/bug_bts_8609`
- `_06_issues/_12_2h/bug_bts_8912`
- `_06_issues/_12_2h/bug_bts_9343`
- `_06_issues/_12_2h/bug_bts_9923`
- `_06_issues/_13_1h/bug_bts_10702`
- `_06_issues/_13_1h/bug_bts_9591`
- `_06_issues/_13_2h/bug_bts_11921`
- `_06_issues/_14_1h/bug_bts_11407`
- `_06_issues/_14_1h/bug_bts_12843`
- `_06_issues/_14_1h/bug_bts_13352`
- `_06_issues/_14_1h/bug_bts_8147`
- `_06_issues/_14_2h/bug_bts_14216/bug_bts_14216_01_basic`
- `_06_issues/_15_1h/bug_bts_13646/_04_check_backup_time`
- `_06_issues/_15_1h/bug_bts_15290`
- `_06_issues/_15_1h/bug_bts_16667`
- `_06_issues/_15_2h/bug_bts_17709`
- `_06_issues/_17_1h/cbrd_20659/check_newpasswod_sha2`
- `_06_issues/_17_2h/bug_bts_8927`
- `_06_issues/_20_2h/cbrd_22803`
- `_06_issues/_22_1h/apis_882`
- `_06_issues/_23_2h/cbrd_24879`
- `_06_issues/_24_2h/cbrd_25552`
- `_06_issues/_26_1h/cbrd_26059`
- `_08_shard/_50_cubridsus/bug_bts_10012`
- `_10_plcsql/cbrd_25873`
- `_12_javasp/case_caution_10`
- `_24_apricot/_06_key_locking/subclass_locks`
- `_26_apricot_qa/_03_performance/_01_locking_enhancement/_01_incons1_sample_index_reverseindex_partition_01`
- `_27_aprium_qa/_01_i18n/issue_9402_collationidentifiers/_02_collation_order_02`
- `_28_features_844/issue_10984_query_profiling/_01_set_trace/_01_set_trace_common`
- `_30_banana_qa/issue_14038_show_threads/_02_extend_01`
- `_30_banana_qa/issue_9328_utc_time`
- `_34_banana_pie/issue_20399_default_ext/20399_loaddb`
- `_35_cherry/issue_21654_server_side_loaddb/cbrd_23340_lineno`
- `_35_cherry/issue_21654_server_side_loaddb/loaddb_CS/_01_utility/_19_loaddb_parameter/mysql_migration`
- `_35_cherry/issue_21654_server_side_loaddb/loaddb_CS/_06_issues/_12_2h/bug_bts_8497`
- `_35_cherry/issue_21654_server_side_loaddb/loaddb_CS/_26_apricot_qa/_02_sql_extension3/_04_pseudocolumn_in_default_clause/_01_load_unload`
- `_35_cherry/issue_22172`
- `_36_damson/cbrd_23608_tde/tbl_enc_18`
- `_37_elderberry/cbrd_23841_flashback/cbrd_23841/string_test/collation_test`
- `_37_elderberry/cbrd_23842_cdc/bug/cbrd_27026`
- `_37_elderberry/cbrd_23842_cdc/supp/supp06`
- `_37_elderberry/cbrd_23954/use_delete`
- `_39_fig_cake/cbrd_24044_enhance_optimizer/cbrd_25080`
- `_35_cherry/issue_21506_online_index/cbrd_22589_hang_dwb`
- `_35_cherry/issue_21654_server_side_loaddb/loaddb_CS/_01_utility/_19_loaddb_parameter/parameter_combine`
- `_05_addition/bug_xdbms_sus1092`
- `_06_issues/_11_1h/bug_bts_4321_2`
- `_06_issues/_11_1h/bug_bts_5057`
- `_06_issues/_11_1h/bug_bts_5577`
- `_06_issues/_11_2h/bug_bts_6237`
- `_06_issues/_12_1h/bug_bts_6720`
- `_06_issues/_12_1h/bug_bts_7592`
- `_06_issues/_12_2h/bug_bts_10298`
- `_06_issues/_12_2h/bug_bts_7170`
- `_06_issues/_12_2h/bug_bts_7833`
- `_06_issues/_12_2h/bug_bts_8363`
- `_06_issues/_12_2h/bug_bts_8780`
- `_06_issues/_12_2h/bug_bts_9073`
- `_06_issues/_12_2h/bug_bts_9602_2`
- `_06_issues/_13_1h/bug_bts_10350`
- `_06_issues/_13_1h/bug_bts_11552`
- `_06_issues/_13_2h/bug_bts_11466`
- `_06_issues/_13_2h/bug_bts_12516`
- `_06_issues/_14_1h/bug_bts_12581`
- `_06_issues/_14_1h/bug_bts_13143`
- `_06_issues/_14_2h/bug_bts_12050`
- `_06_issues/_14_2h/bug_bts_15375`
- `_06_issues/_15_1h/bug_bts_14696`
- `_06_issues/_15_1h/bug_bts_16258`
- `_06_issues/_15_1h/bug_bts_9349`
- `_06_issues/_16_2h/cbrd_20510`
- `_06_issues/_17_1h/cbrd_20760_2`
- `_06_issues/_19_1h/cbrd_22423`
- `_06_issues/_21_1h/cbrd_23859`
- `_06_issues/_22_2h/cbrd_24536`
- `_06_issues/_24_1h/cbrd_25360`
- `_06_issues/_25_1h/cbrd_26020`
- `_06_issues/_26_2h/cbrd_27172`
- `_09_64bit/_01_filesize/_01_pg4k`
- `_10_plcsql/isolation_commit_rollback/_02_repeatable_read/test05`
- `_24_apricot/_02_filtered_index`
- `_26_apricot_qa/_02_sql_extension3/_03_error_enhancement/_01_cubrid_error_05`
- `_26_apricot_qa/_04_i18/general/_00_issues/bug_bts_8805`
- `_27_aprium_qa/_01_i18n/issue_9404_showcollation/_11_coercibility_02`
- `_29_features_920/issue_10160_common_collations/_02_rm_common_collations_file`
- `_30_banana_qa/issue_14183_make_tz/make_tz_test/07_make_tz_new_extend/08_make_tz_extend`
- `_32_features_930/issue_12506_show_heap_header/_01_show_heap_header`
- `_35_cherry/issue_21654_server_side_loaddb/bigPageSize`
- `_35_cherry/issue_21654_server_side_loaddb/loaddb_CS/_01_utility/_17_loaddb/bug_xdbms256`
- `_35_cherry/issue_21654_server_side_loaddb/loaddb_CS/_06_issues/_11_2h/bug_bts_5703`
- `_35_cherry/issue_21654_server_side_loaddb/loaddb_CS/_06_issues/_14_2h/bug_bts_14100`
- `_35_cherry/issue_21654_server_side_loaddb/periodic_commit`
- `_36_damson/cbrd_23608_tde/log_enc_04`
- `_36_damson/cbrd_23608_tde/utility_12`
- `_37_elderberry/cbrd_23842_cdc/api/api12`
- `_37_elderberry/cbrd_23842_cdc/dml/insert/insert01`
- `_37_elderberry/cbrd_23844/cbrd_24330/flashback`
- `_38_fig/cbrd_24563/_dev_04_spec_chars_cf`
- `_39_fig_cake/cbrd_25848`
</details>

===== 2026-09-02T05:40:27Z https://github.com/xmilex-git/workspace/issues/176#issuecomment-5504997602
**보충 — 워커 최종 보고 취합: A(CAS 프로세스 모델)로 묶였지만 제품 결함/결정이 필요한 시그니처 (본문 코멘트 정정·추가)**

본문 A 카테고리 129건 중 아래 8묶음(약 30건)은 "TC가 없어진 구조를 센다"가 아니라 **제품 동작 회귀 또는 호환성 결정 사안**으로 봐야 한다. 부록 표의 카테고리는 그대로 두고 여기서 재분류한다.

| 시그니처 | TC | 건수 | 판정 |
|---|---|---|---|
| **`kill <tranid>` / `kill query` / `kill transaction` 문이 대상 세션을 중단시키지 못함** — `has been aborted`/`Has been interrupted`/`1 transaction killed` 전부 0회 | `bug_bts_13845`(14 sub-case 전부), `bug_bts_14303`(`select sleep(300)` 미중단), `bug_bts_14305` | 3 | **PRODUCT** — 세션 kill이 CAS 프로세스 시그널에 의존했다면 in-server driver_session에 대한 인터럽트 전달 경로가 빠진 것. 최우선 |
| **서버 .err에 `stran_server_auto_commit_or_abort: transaction committed.` 로그 미출력** | `_30_banana_qa/issue_22015_QEWC/*` (big_data_1/2, cci_api, cci_ds, cci_holdability, error_test_1/2, holdability_1/2, jdbc_dbcp, operation_type) | 11 | **PRODUCT** — 오토커밋 경로가 CAS의 `stran_server_auto_commit_or_abort` 호출을 거치지 않게 바뀐 듯. 로그만이 아니라 오토커밋 경로 자체가 바뀐 것인지 확인 필요 |
| **`num_tran_rollbacks`가 단발 `csql -c` 접속 횟수(40)만큼 정확히 증가** (statdump 120 vs 80) | `_35_cherry/.../cbrd_24644` | 1 | **PRODUCT** — 커밋 성공 후에도 thin 세션 종료 시 rollback 1회가 추가 계상됨. 세션 teardown 경로 |
| **`show access status`에서 접속 사용자 행/HOSTNAME/프로그램명 상실** (`'DBA' NULL NULL NULL`만 남음), `bug_bts_13392`는 세션 `intl_*` 파라미터도 기본값 회귀 | `bug_bts_13339`, `bug_bts_13392` | 2 | **PRODUCT** — 접속 시 CAS가 릴레이하던 클라이언트 식별 정보(host/program/user)가 서버 세션에 안 채워짐. `driver_session` 프로그램명 노출(본문 A-④)과 같은 뿌리 |
| **구버전 JDBC 드라이버(9.3.0.0206 번들) 및 `Attempt to use a not supported service[CAS INFO-localhost:13091,0]` 거부** | `bug_bts_17595_2`(14 sub-case), `bug_bts_10502/10503/10505/10507/10509/10519/10521` 계열 | 8 | **결정 사안** — #116 D3(V12 단일, 구버전 방언 미승계)에 따른 의도된 거부인지 확인. 의도라면 TC 제외, 아니면 핸드셰이크 호환 버그. `_40_guava/cbrd_26401` shard JDBC의 NPE도 같은 `CAS INFO` 접속 문자열 계열 |
| **브로커 기동 거부: `config error, <br>, DIRECT_HANDOFF with SSL requires DIRECT_HANDOFF_SSL_DB`** | `cbrd_23613_1/_5`, `cbrd_23688_1/_4/_5` | 5 | **결정 사안** — SSL 브로커에 신규 필수 파라미터. 기존 conf 호환(기본값 유도)을 넣을지, TC conf를 고칠지 결정 |
| **브로커 `sql_log/`·`error_log/`·`*.slow.log`·ddl_audit(`<br>_1_ddl.log`, `csql_<db>_ddl.log`) 디렉터리/파일 자체가 생성되지 않음** (재배치가 아니라 부재) | `cbrd_24416`(비밀번호 마스킹), `cbrd_24438`, `cbrd_23915`, `cbrd_24517`, `cbrd_20759`(cubrid_replay), `cbrd_24679`, `cbrd_25209`, `cbrd_25233`, `cbrd_26038`, `cbrd_25511`, `apis_869/877`, `castest/csqltest` 등 | ~17 | **결정 사안(제품)** — SQL 로그/슬로우 로그/DDL 감사 로그는 운영 기능. 서버측 `cas_*` 로그로 대체 제공되는지, 경로·파일명 계약을 어떻게 잡을지 #116 후속 결정 필요. 결정 전까지 TC 대량 NOK 지속 |
| `show threads` 고정 스레드 수(217→218, 204→205), `cubrid broker status` OFF 카운트 폴링 미수렴 | `issue_14038_show_threads/_01_basic,_02_extend_03`, `issue_10952/_03_session_persistence` | 3 | TC — 신규 adoption/session 워커 스레드로 수치 변화. 기대값 갱신 |

**본문 정정**: A의 "대부분 TC측" 판정은 위 8묶음을 제외한 나머지(per-CAS sql_log 파일명 grep, `broker add/drop/restart`, `ps | grep cub_cas`, 소켓 파일)에만 적용된다. 위 표의 PRODUCT 3묶음(kill 문, QEWC 커밋 로그, rollback 계상)은 본문 §4 우선순위 2번(제품 수정) 목록에 H·B 다음으로 추가한다.

워커별 원 보고: GROUP0~5 히스토그램 합계 = CAS 129 / UNKNOWN 76(CDC 60 포함) / THIN 58 / SHARD 41 / SERVER_SIDE 21 / TIMEOUT 17 / ADOPTION 13 / CRASH 8 / PLCSQL 3 / HA 1 / ENV 1 = 372 (본문 표와 일치, 본문은 CDC·직결 CS를 B로 분리 집계).

