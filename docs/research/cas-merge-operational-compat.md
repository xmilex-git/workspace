# CAS 통합 운영 호환 수정과 검증

대상은 [운영 호환 구현 잔여 — 로그·동적 제어·접속 종류·query replace](https://github.com/xmilex-git/workspace/issues/222)다. [확정 운영 정책](https://github.com/xmilex-git/workspace/issues/209#issuecomment-5559332086)에 따라 사용자 진단 기능과 설정 효과를 복구한다. 전체 셸 스위트의 최종 판정은 별도 최종 게이트 티켓이 담당한다.

## 기준과 결과

- 수정 전 엔진: `d1cf63b062e49f392fc5e4dfa932e106c97c8e7d`, 원본 TC `f5ca3fd222128a02f750bf47032dfa3d6fc92e42`.
- 최종 엔진: `02b9bb4b02bd3a911ae8036de95f0201c8b4a95e` — [기존 엔진 PR](https://github.com/CUBRID/cubrid/pull/7837)에 반영.
- 최종 TC: `2c2c55caec220dffead6236a19b642045267a0d3` — [기존 TC PR](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4040)에 반영. 원본 4건의 기대값은 유지했다.
- JDBC: `11.4.0.0075`, SHA256 `3e876fb189ea55fe7f6d2481b6f79e02c8c8c222c38543f10c2f73c693e5f564`.

| 최종 검증 | optdebug | release |
|---|---|---|
| 빌드 | 성공 | 성공 |
| `test_server_compile` | 20/20 | 20/20 |
| 표준 smoke 5종 | 전부 통과 (`smoke.sh` 14/14) | 전부 통과 (`smoke.sh` 14/14) |
| 원본 4건 + 확장 TC | 5/5 | 5/5 |
| 코어 | 0 | 0 |

빌드 트리는 이번 캠페인에서 새로 만들었다. `bff0840db`의 최초 빌드 이후 GitHub 서식 수정과 필수 메모리 헤더를 포함한 최종 `02b9bb4b0`로 갱신하고 변경된 TU·의존 항목을 재컴파일했다. release 최초 시도는 의존 라이브러리 다운로드 504로 실패했으며 최종 head에서 재시도해 성공했다. **모든 최종 unit·CTP·smoke는 두 설치본의 `02b9bb4` 버전 확인 후 실행했다.** 이전 캠페인의 빌드 객체는 재사용하지 않았다. CI formatter는 수정된 9개 파일의 scratch 사본에서 차이 0, 필수 메모리 헤더는 마지막 include로 확인했다.

| 원본 TC | 수정 전 실패 | 최종 양 모드 판정 |
|---|---|---|
| `bug_bts_9611` | 접속 실패가 IOException이 되어 CAS/SESSION/URL 진단 누락 | 통과 |
| `bug_bts_10665` | 제약 위반 오류의 SQL_ID·SQL 문장 기록 누락 | 통과 |
| `cbrd_24335` | csql DDL 감사 로그의 파일명 불일치 | 통과 |
| `cbrd_26410` | 서버 SQL trace와 브로커 slow 로그 내용 누락 | 통과 |

컨테이너 provenance와 JUnit 결과에서 최종 TC SHA·실제 5개 케이스·실패/오류/skip 0을 확인했다. 확장 TC는 6개 성공 표식을 출력하며 오류 로그 복구와 실제 1초 timeout을 포함한다. CTest에는 이 unit 바이너리가 등록되지 않으므로 `0 tests`를 통과 수로 세지 않는다. unit 수는 한 실행의 내부 검사 20개 기준이다.

## 수정 경계

### Query replace

브로커가 만든 규칙 세그먼트의 key와 소유 브로커 ID를 내부 handoff에 전달한다. 서버 세션은 자기 규칙 mapping·정규화 버퍼·marker 검증 캐시·실패 누적 상태를 보유하고 prepared handle을 정리한 뒤 해제한다. 서로 다른 브로커·사용자·동시 세션이 실행 상태를 공유하지 않는다.

기존 add/reload/disable/enable과 append-only 규칙 슬롯을 사용한다. reload 전에 준비한 handle은 기존 규칙을 계속 참조한다. SHOW SESSION STATUS에 `Num_query_replace_prepare`, `Num_query_replace_execute`, `Num_query_replace_fallback`을 추가했다.

### 실행·접속 진단

native `qmgr_execute_query`에도 기존 RPC 처리기의 오류 SQL_ID·slow trace·CAS 로그용 진단 텍스트를 연결했다. 진단이 SQL 문자열을 사용하는 동안 XASL 캐시 참조를 유지하고, 진단 과정의 오류가 원래 질의 오류를 바꾸지 않게 한다. 이미 수집 중인 perfmon 상태도 보존한다. 기존 trace 파일과 latest 링크의 이름은 변경하지 않는다.

thin csql은 `APP_NAME_CSQL`로 DDL 로거를 초기화하여 `csql_<db>_ddl.log`를 생성한다. 브로커는 첫 ACK 이후의 cleartext 접속 거절을 CAS 응답 프레임으로 보내며 기존 재시도 오류코드를 유지한다. 드라이버 V12 메시지 형식은 변경하지 않았다. 확장된 구조체는 브로커–서버의 내부 제어 프로토콜이다.

### 트랜잭션 종료와 로그 회전

서버 요청 루프에 기존 CAS 루프의 첫 요청 표시 해제, DONE/접근 시각 갱신, 트랜잭션 타이머 초기화를 복원했다. cursor/handle close가 진행 중인 트랜잭션을 INACTIVE로 잘못 알리면 드라이버가 COMMIT을 생략할 수 있다. 새 TC는 다른 연결의 commit 가시성과 rollback 결과를 검사하고, 완료된 SQL/slow 로그가 실제로 회전하는지도 확인한다.

## 설정별 적용 범위

| 설정 | 대상과 적용 |
|---|---|
| SQL_LOG, SLOW_LOG | `<database>:<Session_id>`를 지정하면 그 세션만 변경. 생략하면 브로커 기본값과 기존 소속 세션 전체를 덮어쓴다. 기존 연결의 다음 요청부터 반영한다. |
| SQL_LOG_MAX_SIZE, LONG_QUERY_TIME, LONG_TRANSACTION_TIME | 브로커 전용. 기존 세션의 다음 요청부터 새 상한·판정 기준을 사용한다. |
| ACCESS_LOG, ACCESS_LOG_MAX_SIZE | 브로커 전용 실행 설정으로 전달한다. |
| JDBC_CACHE, JDBC_CACHE_HINT_ONLY, JDBC_CACHE_LIFE_TIME | 브로커 전용. 세션 소유 스레드의 설정 스냅샷에 반영한다. |
| STATEMENT_POOLING, MAX_PREPARED_STMT_COUNT, MAX_QUERY_TIMEOUT, TRIGGER_ACTION | 브로커 전용. 필요한 세션 상태에도 반영한다. 준비 문장 상한의 감소는 허용하지 않는다. |
| SESSION_TIMEOUT | 선행 결정의 서버 설정 기본값(통상 -1)을 유지한다. 명시적 broker_changer 변경 이후에는 해당 브로커의 기존·신규 세션에 적용한다. 무조건 기존 브로커 기본 300초를 적용하지 않는다. |
| LOG_DIR, SLOW_LOG_DIR | 브로커별 디렉터리와 `<broker>_<N>` 파일명 유지. 디렉터리 변경은 기존의 트랜잭션 로그 종료·재개 경계를 사용한다. |
| ERROR_LOG_DIR | 다음 오류부터 해당 브로커 세션의 `<broker>_<N>.err`에 같은 형식의 오류 기록을 남긴다. DB 서버의 원래 `.err` 기록은 유지한다. 파일 열기·쓰기 실패는 원래 로그에 한 번 보고하며 질의 오류를 바꾸지 않는다. |
| CCI_PCONNECT, ACCESS_MODE | 기존 접속 프런트 설정 경로를 유지한다. |

브로커 전용 설정에 세션 선택자를 붙이면 거절한다. 다른 설정 변경은 SQL_LOG/SLOW_LOG의 개별 모드를 덮지 않는다. 운영 중 변경은 파일에 저장하지 않는다. 직접 csql은 브로커 설정 대신 기존 서버 `cas_*` 기본값을 사용한다.

보충 검증에서 MAX_QUERY_TIMEOUT의 동적 변환이 밀리초를 저장하고 기존 소비자가 다시 1000배 하는 오류를 발견했다. `5` 입력의 실제 제한이 5,000초였다. 최종 구현은 기존 파일 설정·CLI와 동일하게 초 단위를 저장한다. 새 TC는 같은 열린 연결에 `1s`를 적용하고 CPU 질의 중단 및 `1000 ms (from broker)` 기록을 확인한 뒤 제한을 해제하고 연결을 재사용한다. 수정 전 `85dddee91`에서는 이 추가 단언만 실패했다.

SQL_LOG2는 [선행 B2 결정](https://github.com/xmilex-git/workspace/issues/139#issuecomment-5460809662)의 명시적 은퇴 항목이다. GET_QUERY_INFO의 플랜 파일 경로는 유지한다. 사라진 CAS 프로세스의 메모리·풀·재시작·재접속 계층 설정과 SHARD 지원을 이 작업에서 되살리지 않는다.

## 회귀·운영 검증

새 `shell/_40_guava/cas_merge_query_replace`는 다음 실제 경로를 검사한다.

- 두 브로커가 같은 SQL을 다른 결과로 치환하며, 다른 사용자와 동시 세션은 격리된다.
- bind 재배치, prepare 실패 시 원래 SQL로 복귀, 규칙 add/reload/disable/enable, 기존 prepared handle 수명과 카운터.
- cursor/handle close 이후 commit/rollback, SQL 및 slow 로그 회전.
- 살아 있는 연결의 ERROR_LOG_DIR 변경, 다른 브로커 격리, DB 오류 로그 보존.
- 동적 MAX_QUERY_TIMEOUT의 초 단위 적용, 실제 CPU 질의 중단과 연결 재사용.
- 로그 파일 경로가 디렉터리여서 쓰기가 실패해도 질의 오류는 보존되며, 장애 제거 후 같은 설정을 재적용하면 기록이 재개된다. CTP 재시도 때 자체 생성 규칙을 초기화한다.

`8691230c7` optdebug에서 기존 SQL_LOG·SLOW_LOG 제어 행렬을 모두 통과했다. 각 행렬은 22개 동작 단계와 최종 성공 표식을 출력했다. 두 DB·두 브로커, 실제 `database:Session_id` 선택, 전체 덮어쓰기, 신규 연결 상속, 미커밋 트랜잭션과 브로커 재시작 후 기존 연결을 검사했다. 이후 오류 로그 재개·timeout 단위·필수 메모리 헤더를 수정했다. 해당 차이는 최종 양 모드 확장 TC와 표준 게이트에서 검증했다. SQL/SLOW 전체 행렬 자체를 최종 head에서 다시 실행했다고 주장하지 않는다.

검증하지 않은 드라이버 플랫폼이나 전체 셸 green은 주장하지 않는다. 전체 셸 CI 최종 판정은 [최종 게이트](https://github.com/xmilex-git/workspace/issues/234)에서 진행한다.

표준 smoke는 최종 `02b9bb4b0`의 양 모드에서 `smoke.sh` 14/14, `smoke_thin`, `smoke_csql`, `smoke_gate`, `smoke_jdbc` 모두 통과했다. JDBC plain·TLS·read-only 및 SQL/slow/access/DDL 로그 생성·`broker_log_top` 분석을 포함한다. `smoke_gate`의 선택적 legacy-csql 비교는 별도 바이너리를 제공하지 않아 생략했고, TLS 배터리의 XA/alt-hosts는 기존 하네스 설계상 생략한다. plain 배터리는 해당 단계를 실행했다.

하네스 설정은 기존 단언을 유지하며 `MAX_PREPARED_STMT_COUNT=64`, `LONG_QUERY_TIME=1s`, `ACCESS_LOG=ON`을 브로커 설정에 명시했다. 서버의 `cas_*` 값만 바꾸면 브로커 연결의 설정을 바꾸지 못한다. PL smoke를 위해 자체 세션 설정의 `stored_procedure=yes`를 사용했다. 전체 런타임 사본·서버 래퍼·독립 포트/공유 메모리를 사용했고 완료 후 자체 프로세스와 포트 할당을 정리했다.

### 실제 접속 식별과 로그 재생

보충 운영 검증은 `8691230c7`에서 실제 CCI·JDBC·local thin csql의 열린 연결에 대한 `Client_type`을 확인했다. csql은 `__direct__`로 관측됐으므로 여기서 브로커 경유 신원을 확인했다고 해석하지 않는다. 실제 `cubrid_replay`는 생성된 SELECT 로그 한 건을 새 연결로 실행했으며 skip 0/fail 0이었다. 원본 서버 SQL 로그에서도 새 session id 9의 같은 SELECT 실행과 rollback을 확인했다. `broker_log_top`·`broker_log_converter`도 같은 파일을 처리했다. 유효한 `database:Session_id`의 MAX_QUERY_TIMEOUT은 브로커 전용이라는 이유로 거절하고, 같은 선택자의 SQL_LOG 변경은 허용했다.

### 검증 환경의 기존 경로 길이 제한

깊은 scratch 경로에서는 SQL/slow 로그가 기대한 하위 디렉터리와 다른 위치에 생성되었다. 짧은 symlink를 설치 경로로 사용하면 같은 바이너리와 설정으로 행렬이 통과했다. 기존 `CONF_LOG_FILE_LEN=128` 및 `make_abs_path()`의 `snprintf(..., dest_len, ...)` 뒤 길이 검사 때문에 잘린 경로를 성공으로 처리할 수 있다. 두 파일은 이번 변경 전 기준과 동일하다. 이 관찰과 기존 제한은 결함 통합 기록에 남기며 이번 세션 제어 수정에 경로 길이 확장을 포함하지 않는다.

## 추적과 증거

상세 결함의 단일 기록은 [query replace 결함](https://github.com/xmilex-git/workspace/issues/210#issuecomment-5573907190)과 [진단·접속·트랜잭션·설정 전달 결함](https://github.com/xmilex-git/workspace/issues/210#issuecomment-5574476350)이다.

오류 로그 복구와 기존 경로 길이 제한은 [후속 결함 기록](https://github.com/xmilex-git/workspace/issues/210#issuecomment-5575207085)에 정리했다.

MAX_QUERY_TIMEOUT의 단위 오류와 실제 재현은 [운영 제어 추가 결함](https://github.com/xmilex-git/workspace/issues/210#issuecomment-5575369511)에 기록했다.

중간 증거는 툴링 `.git_ignored_dir/scratch/`에 보존했다.

- `herdr-integration/wf222-repro-20260908T015808/report3.md`: 정본 수정 전 원본 4건.
- `herdr-integration/wf222-control-20260908T022354/report2.md`: 제어 행렬 및 회전 재현.
- `herdr-integration/wf222-qr-gate-20260908T022143/report2.md`: query replace 초기 unit/CCI 검증.
- `herdr-integration/wf222-diag-gate-20260908T025256-36e2/report2.md`: 원본 4건 + 확장 TC 5/5.
- `ctp-run-out/shell-20260907T183017Z-2123806/`: 해당 컨테이너 실행의 원본 결과와 provenance.
- `herdr-integration/wf222-final-gate-20260908T034838-452a/report3.md` 및 `build-logs/{DynamicLogProbe,SlowLogProbe}-run2.log`: 전체 로그 제어 행렬. 보고서의 단언 개수 설명보다 원본 로그의 22개 동작 단계와 최종 표식을 기준으로 한다.

- `herdr-integration/wf222-complete-build-20260908T043951-0184/report.md`: 중간 `85dddee91`의 양 모드 빌드·unit·CTP.
- `herdr-integration/wf222-complete-build-20260908T043951-0184/report2.md`, `smoke-logs/`: 중간 `85dddee91`의 양 모드 표준 smoke 5종.
- `ctp-run-out/shell-20260907T200535Z-2504070/`: optdebug 5/5.
- `ctp-run-out/shell-20260907T200823Z-2524808/`: release 5/5.
- `ctp-run-out/shell-20260907T201103Z-2546584/`: optdebug 확장 TC 재실행 1/1.

- `herdr-integration/wf222-ops-probe-20260908T050727-78bf/report{,2}.md`: 실제 client identity·로그 재생·scope 거절과 timeout 결함 재현. 원래 잘못된 위치에 쓴 증거는 `wf222/ops-evidence/`로 모두 이동했다.
- `ctp-run-out/shell-20260907T202909Z-2573128/`: `85dddee91` + TC `2c2c55cae`의 예상 실패. 기존 단계는 통과하고 추가 timeout 단언만 실패.

최종 증거:

- `herdr-integration/wf222-timeout-gate-20260908T052905-d7e0/report.md`: 최종 양 모드 게이트. 보고서의 RED 기준 `8691230c7` 표기는 실제 실행 provenance에 따라 `85dddee91`로 정정한다.
- `wf222-timeout-gate/build-logs/`: 새 빌드 트리 생성부터 최종 head 재컴파일·설치까지의 로그.
- `wf222-timeout-gate/unit-logs/{optdebug,release}-run1.log`: 각 내부 검사 20개 통과. 워커가 반복 실행한 횟수를 별도 테스트 개수로 세지 않는다.
- `wf222-timeout-gate/smoke-logs/`: 양 모드 5종. tracer 로그 파일명은 `smoke-{optdebug,release}.log`다.
- `ctp-run-out/shell-20260907T210851Z-2684468/`: 최종 optdebug 5/5, 코어 0.
- `ctp-run-out/shell-20260907T211156Z-2703599/`: 최종 release 5/5, 코어 0.

자체 서버·브로커 프로세스와 포트 할당을 정리했고, 작업별 Herdr 세션도 종료 확인 후 삭제했다. 검증 보고서와 원본 로그는 유지했다.
