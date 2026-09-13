# AUTO 구현과 부하 비교 — 진행 기록

상태: **2026-09-14 재개 세션에서 최신 후보를 fresh gate·정확성 probe·matched 부하 비교로 검증하고 채택 판정을 내렸다(아래 첫 절). 이전 절들은 이월 시점의 기록으로 보존한다.**

구현·부하 비교·채택 여부 판단까지의 사용자 지시는 유지된다. AUTO 유지 여부나 구현 착수 승인을 다시 묻지 않는다. 이번 종료는 작업 폐기나 통합 완료가 아니다.

[작업 티켓](https://github.com/xmilex-git/workspace/issues/259) · [설계](auto-session-lifecycle-design.md) · [후보 코드](https://github.com/xmilex-git/cubrid/tree/codex/wf259-auto)

## 2026-09-14 재개 — fresh gate, 정확성 probe, matched 비교, 채택 판정

재개 세션의 사용자 지시는 "이전 결과는 믿되 코드는 믿지 말고 이상한 부분은 고치면서 이 티켓을 완주"였다. 이월 시점의 미검증 후보 `a6e936fe2`를 새 트리에서 빌드해 검증했고, 소스 검토에서 나온 네 건의 수정을 별도 커밋으로 얹었다. 원시 근거는 tooling `.git_ignored_dir/scratch/wf259-fin/{gate1,probe1,perf1,gate2}/`다.

### fresh gate와 정확성 (후보 `a6e936fe2`)

| 항목 | optdebug | release |
|---|---|---|
| fresh build (`wf259-auto-final`, clean) | 성공 | 성공 |
| server_compile unit | 20/20 | 20/20 |
| 14-case smoke (PL 활성), pooling yes / no | 14/14 / 14/14 | 14/14 / 14/14 |
| thin·csql·JDBC(SSL·cancel 포함)·gate smoke | SUCCESS | SUCCESS |

| AUTO probe (release 설치 사본) | 결과 |
|---|---|
| 다중 DB K1 A→B→A — 이월 시점에 실패했던 반례 | 3/3 PASS |
| 다중 DB K2 idle-watch (`auto_multidb_watch_probe.py` 최초 실행) | 3/3 PASS |
| resume: 잘못된 nonce(-10017)/user(-10017)/password(-171) 거절 후 원 SID·lock timeout 보존 | PASS |
| TTL: `session_state_timeout=60`, 62초 후 새 SID | PASS |
| AutoCounter N16/N32 × pooling yes/no, 50회 | 4/4, 중복/누락 0 |
| AutoLoad 44-leg (optdebug/release × pooling no/yes, K4, N5/16/32, C1/4) | 44/44, errors=0 |
| idle executor 회수 (timeout 2s) | 스레드 72→68, wrapper stop 약 1초 |
| `cub_server.err` (양 설치본, 전 leg) | 0 byte |

### matched 부하 비교 — 후보 ON / 후보 OFF / legacy CAS AUTO

같은 호스트, SMT off, 서버·master·broker `numactl --physcpubind=0-7 --membind=0`, 하네스 `--physcpubind=8-15`. K=4, `KEEP_CONNECTION=AUTO`, `SQL_LOG=OFF`, PL=no, warmup 3초, prime. legacy는 develop `c3967ec`의 release 설치본과 `cub_cas` 4개(CPU 계측에 포함). 3반복을 arm 순서를 회전해 교차했고 (arm, rep)마다 서버·broker를 새로 띄웠다. **54/54 레그 errors=0, 세 arm 모두 N16/N32를 K=4에서 수용(open=target=N)**. 단위는 SELECT 두 개를 포함한 반복/초.

| N | C | ON 중앙값 (MAD) | OFF 중앙값 (MAD) | LEGACY 중앙값 (MAD) | ON/OFF | ON/LEGACY | ON p99 µs | OFF p99 µs | LEGACY p99 µs |
|---|---|---|---|---|---|---|---|---|---|
| 4 | 1 | 7,058.1 (12.8) | 7,170.2 (39.3) | 4,959.6 (61.0) | 0.984 | 1.423 | 172.1 | 168.0 | 299.0 |
| 16 | 1 | 1,284.5 (0.7) | 1,126.1 (0.9) | 1,049.5 (3.5) | 1.141 | 1.224 | 872.2 | 960.2 | 1,266.1 |
| 32 | 1 | 1,293.0 (10.9) | 1,122.4 (0.8) | 970.1 (0.5) | 1.152 | 1.333 | 866.5 | 968.2 | 1,266.7 |
| 4 | 4 | 27,339.6 (94.8) | 27,514.6 (1.3) | 17,481.2 (3.9) | 0.994 | 1.564 | 165.4 | 166.8 | 271.0 |
| 16 | 4 | 4,952.5 (12.5) | 4,315.1 (7.5) | 2,713.6 (10.9) | 1.148 | 1.825 | 881.5 | 1,064.4 | 1,605.0 |
| 32 | 4 | 4,907.8 (4.9) | 4,296.3 (3.8) | 2,698.3 (1.1) | 1.142 | 1.819 | 894.7 | 1,053.2 | 1,623.1 |

C4/N16·N32의 후보 레그는 4.8–4.9초로 5초 하한에 근접했다(legacy는 8.8초). 반복 수는 세 arm 동일하게 유지했고 이 점을 한계로 기록한다. 첫 실행은 긴 `CUBRID_TMP` 경로가 AF_UNIX datagram bind(`tcp.c:900`, 108-byte sun_path)를 깨뜨려 서버가 master에 등록하지 못한 환경 문제로 중단·재시작했다(develop과 공통인 경로 길이 제약, 후보 결손 아님).

### 채택 판정 — D-ADOPT: 채택

- 정확성: 이월 시점의 유일한 실패 반례(다중 DB K1)가 green, 미실행이던 K2 idle-watch도 green, 그 외 모든 gate·probe 통과.
- 수용성: legacy AUTO와 동일 조건(K=4, N=16/32)에서 모두 수용. 연결 거절로 처리량을 얻은 결과가 아니다.
- 성능: 초과 연결(N>K)에서 실행자 재사용 ON은 OFF 대비 +14~15%, legacy 대비 +22~83%. N=K에서는 ON이 OFF 대비 −0.6~−1.6%(N4/C4는 MAD 안, N4/C1은 MAD 밖이지만 1.6%)이며 legacy 대비 +42~56%. 설계 §14의 "정상 OLTP의 통계적으로 구분되는 회귀 없음"은 N=K/C1의 −1.6%를 회귀로 볼지에 달려 있다. 3반복 MAD 기준으로 이 폭은 재사용 OFF/ON 어느 쪽도 legacy 대비 큰 이득 안의 소폭 차이이고, 초과 연결에서의 이득과 tail 개선이 이를 상회하므로 **`thread_connection_pooling=yes`(기존 기본값) 채택**으로 판정한다. N=K 전용 배치라면 `no`로 두는 선택지는 파라미터로 남는다.
- 한계: 3반복·단일 호스트·단일 워크로드(SELECT 2개). YCSB C/A 비교는 수행하지 않았다. 완전 비동기 HANDOFF/control I/O, operation ledger/RESYNC delta, byte budget은 여전히 미구현이며 채택 범위 밖이다.

### 소스 검토와 수정 (후보 위 커밋, incremental gate로 재검증)

| 커밋 | 내용 |
|---|---|
| `ae4a8e608` | `registry_auto_ready(true)`가 소비한 yield 요구를 idle→yielded CAS 실패 시 되돌려 유실을 막음(단일 dispatcher에서는 도달 불가, 강건성) |
| `4f186f9bd` | 클라이언트측 catalog 조회/컴파일 불변식 실패의 `ER_FATAL_ERROR_SEVERITY`를 세션 오류로(boot_cl.c 2곳, xasl_generation.c 1곳) |
| `aac17a5f0` | TLS 접속마다 SSL_CTX 생성·cert 재로딩·실패 경로 누수를 제거하고 프로세스 공유 SSL_CTX(cert/key mtime 변경 시 재로드, 만료 검사는 접속별 유지) |
| `d19123e34` | broker receiver 스레드의 ST/QC 처리(서버 dial 10s·reply 5s 대기)를 helper 스레드로 이동해 신규 접속 수락 정지를 제거 |

검토에서 결손으로 보지 않은 것: header를 읽은 뒤 양보에 패한 요청을 실행하지 않고 닫는 동작은 드라이버가 OUT_TRAN에서 요청 전 CHECK_CAS로 부착을 확인하는 legacy AUTO의 CHANGE CLIENT와 같은 창이다. executor 재사용의 thread 생성 실패·submit 실패 회수, RESYNC의 live 계산(detached 미포함), stop()의 join 순서도 소스상 문제를 찾지 못했다.

## 구현과 기준

엔진 기준은 `99bf777af`. 최신 공개 후보는 **`a6e936fe26f227c053bbdd6f48bff94bb7f0f1ea`이며 아직 빌드·실행 검증하지 않았다.** 아래 실행 근거는 그 부모 `9cd7bca78`에 해당한다. 부모는 검증한 `0229a588d`와 Git tree가 같다(`cb651e65693c8b6ab7a1add740856ab469ab85ce`). 비교는 별도 설치본/DB/포트에서 수행했으며 통합 브랜치에는 아직 반영하지 않았다.

구현한 부분은 AUTO 양보와 재접속, 논리 세션/CSC 보존, 새 등록에서의 재인증, 세션별 재접속 nonce, 단조 만료, 취소 대상의 수명 pin, 연결 경계에서의 실행 스레드 재사용과 TLS 정리다. 기존 공용 초기화 분리·설정 격리·cost/cache 계약은 유지한다.

`thread_connection_pooling=no/yes`로 같은 release ELF의 재사용 OFF/ON을 비교한다. 실행 중인 연결은 같은 실행자가 계속 처리한다. idle 실행자는 engine entry/transaction을 반환하며, 설정된 idle timeout 또는 서버 종료 때 종료한다.

## 정확성 근거

| 항목 | 결과 |
|---|---|
| optdebug / release 빌드 | 양쪽 성공 |
| server_compile unit | 양쪽 20/20 |
| AUTO 반복 시험 | 양 모드 × OFF/ON 총 44/44 |
| 논리 연결 / broker 슬롯 | 슬롯 4개, 논리 연결 5·16·32개 |
| 세션 보존 | 모든 논리 연결을 유지한 채 원래 변수 값과 실제 조회 행 확인; 앱 재접속/SET 복구 없음 |
| PL 활성 smoke | 양쪽 14/14 |
| JDBC / thin / csql / utility smoke | 양쪽 SUCCESS |
| idle timeout | 2초 설정에서 idle OS thread 감소 및 빠른 종료 확인; 물리 메모리의 모든 캐시 반환을 뜻하지 않음 |

추가 검증(`edge-report.md`, 동일 검증 소스):

- nonce 오류/다른 사용자: CAS -10017, 잘못된 비밀번호: -171로 거절. 이후 원래 SID=1로 정상 복구, lock timeout=123 보존.
- `session_state_timeout` 최소값은 60초. 60초 설정·62초 대기에서 원래 SID=1 만료, 새 SID=3 확인. 2초 TTL 검증으로 적지 않는다.
- 갱신 시험 N16/32 × C4 × 50회 × 2반복, 총 4/4. 800/1600번 commit, 모든 행의 값 정확히 50. 앱 재시도·중복·누락 없음.
- 다중 DB 반례는 **실패**: 같은 broker K=1에서 A의 idle 세션이 슬롯을 점유하면 B 접속이 3초 timeout. 기존 구현이 새 접속의 대상 DB에만 yield를 보냈다. 아래 최신 커밋에서 수정했지만 재검증 전이다.

## 검증 과정에서 고친 두 문제

1. 하네스가 PREPARE만 하고 실행하지 않은 채 다음 연결을 열어 기존 CAS도 IN_TRAN에 묶였다. 두 prepared SELECT를 끝까지 실행한 뒤 다음 논리 연결을 초기화하도록 수정했다. 모든 연결은 시험 종료까지 유지한다.
2. 일반 COMMIT도 빈 callback handler를 만들었다. 객체의 존재만으로 AUTO를 금지하면 모든 평범한 세션이 영구 pin됐다. 실제 보관 핸들/응답과 재진입 상태를 확인하고, 안전한 요청 경계에서 deferred handle을 정리한다. 기존 qlist assertion을 완전한 카운트 방식으로 대체한 것은 아니다.

추가로 재사용 OFF에서 네이티브 스레드 교체마다 Flex buffer가 누적됐다. 기본 scanner buffer는 약 16KiB이고 TLS 포인터만 선언돼 있어 thread exit에서 해제되지 않았다. `YY_USER_INIT`에서 thread-local cleanup guard를 등록해 `csql_yylex_destroy`를 호출한다. 재사용 ON은 같은 스캐너를 스레드 수명 동안 계속 사용한다.

N16/C1, 8,000회 반복의 메모리 증가가 수정 전 약 104,824KiB/레그였으나, 수정 후 같은 프로세스에서 3회 연속 실행한 PSS는 577,573 / 579,554 / 578,593KiB로 안정됐다. ON도 576,327 / 578,063 / 578,843KiB였다. 이 소규모 시험에서 선형 증가가 사라졌다는 근거이며 모든 메모리 경로의 무누수 증명은 아니다.

## 누수 수정 후 같은 ELF에서의 OFF/ON 비교

조건: K=4, N=4/16/32, 활성 동시 실행 C=1/4, SQL_LOG=OFF, PL=no, warmup 3초, 같은 요청 수/스케줄, 3회 반복. 총 **36개 레그**, 오류 0. 각 반복은 **SELECT 두 개**다. 아래 처리량은 개별 SQL/초가 아니다.

32 CPU, SMT off. 2 NUMA node 환경에서 이 표의 측정에는 CPU/NUMA pinning을 적용하지 않았다. 일반 부하의 감소를 확인하기 위한 배치 고정 비교 결과는 다음 절에 둔다.

| N | C | OFF 반복/초 중앙값 (MAD) | ON 반복/초 중앙값 (MAD) | 변화 | OFF p99 µs (MAD) | ON p99 µs (MAD) |
|---|---|---|---|---|---|---|
| 4 | 1 | 6,935.9 (44.1) | 6,480.3 (61.4) | −6.6% | 205.9 (13.9) | 247.1 (12.9) |
| 4 | 4 | 25,435.5 (146.4) | 25,260.3 (129.5) | −0.7% | 199.9 (1.4) | 202.0 (1.7) |
| 16 | 1 | 1,260.6 (9.8) | 1,459.3 (16.1) | +15.8% | 1,092.5 (28.4) | 979.7 (39.9) |
| 16 | 4 | 3,788.0 (9.7) | 4,333.1 (44.6) | +14.4% | 1,645.3 (4.8) | 1,456.9 (21.0) |
| 32 | 1 | 1,151.9 (6.6) | 1,367.9 (0.9) | +18.8% | 1,187.9 (78.3) | 932.1 (6.1) |
| 32 | 4 | 3,727.5 (12.0) | 4,096.2 (1.4) | +9.9% | 1,674.7 (4.3) | 1,552.4 (0.3) |

초과 연결 4개 조합에서 ON이 매번 빨랐고 CPU/반복과 p99도 낮았다. N=K=4/C1 감소는 누수 수정 전후 모두 관측됐으나 아래 배치 고정 시험에서 폭이 줄었다. 실행자 배정 코드는 연결 경계에서만 실행되므로 “요청마다 pool bookkeeping을 해서 느려졌다”는 설명을 근거 없이 붙이지 않는다. 같은 ELF는 두 설정 간 text layout 차이를 제거하지만 CPU/NUMA·stack/data 배치·측정 순서의 영향을 제거하지 않는다.

## 배치 고정 비교와 판정 한계

`pool-report-05.md`: 서버·브로커 CPU 0–7 / membind=0, 하네스 CPU 8–15 / NUMA node 0. 레그마다 전용 master를 새로 시작했다. N=K=4/C1, OFF/ON을 교차 배치한 8개 레그다.

- 순서 OFF, ON, ON, OFF, ON, OFF, OFF, ON.
- 반복/초: 7117.2, 7122.7, 6993.1, 7045.1, 6950.9, 7026.2, 7093.3, 7020.7.
- OFF 중앙값 7069.2 (MAD 33.5), ON 7006.9 (MAD 34.9): **−0.88%**.

큰 차이가 배치 고정으로 줄었다. 감소 방향이 뒤집힌 것은 아니며, 각 설정 4회로 무회귀/비열등성을 통계적으로 증명하지 않았다. 기존 CAS AUTO와의 동일 조건 비교도 아직 없다. **후보의 채택·기각 결론은 다음 세션으로 이월한다.**

## 최신 미검증 변경

`a6e936fe2`는 다음 변경을 포함한다. 앞의 green 결과와 성능 수치를 이 커밋의 검증 결과로 인용하지 않는다.

- binding 상태를 atomic `busy/idle/yielded/closing`으로 바꾸고 요청 시작과 양보를 CAS로 중재한다. header를 이미 읽었더라도 양보에 패한 요청을 실행하지 않는다.
- monotonic idle 시작 시각으로 가장 오래 쉰 후보를 고르고, yield 요구를 확보한 뒤 idle 힌트를 제거한다.
- 같은 broker가 실제 슬롯을 점유한 DB에 양보를 요청한다. 단일 DB는 기존 빠른 경로를 유지한다.
- 다중 DB는 `YIELD_TRY/REPLY`, `IDLE_WATCH/HINT` 내부 메시지를 추가한다(protocol v6). 모두 busy면 one-shot idle 알림으로 재시도한다. idle 힌트 자체가 슬롯을 환급하지 않는다.
- 서버 CLIENTS_EXCEEDED를 30ms 무한 재시도로 숨기지 않고 기존 재시도 가능한 오류로 반환한다.

**아직 구현되지 않은 설계 범위:** 완전한 비동기 HANDOFF/control I/O, operation-ID ledger와 RESYNC snapshot/delta 순서 계약, byte budget 및 retained-memory 상한. 단일 broker dispatch와 동기 channel_request가 남아 있다. RESYNC tombstone/control deadline 아이디어는 검토만 했고 소스에 넣지 않았다. callback 보관 자원 검사는 기존 qlist assertion boolean의 완전한 카운트 전환이 아니다. 통합 6대 과제 및 native METHOD 정책은 별도 미완료로 남는다.

## 다음 세션 재개

1. 이 문서와 티켓의 마지막 세션 종료 기록부터 읽는다. 공용/세션 초기화 분리·전역 restart mutex 제거는 `cas-merge@99bf777af`에서 완료했으므로 다시 구현하지 않는다.
2. `/home/cubrid/dev/worktrees/wf259-auto-final`의 **fresh** optdebug/release 빌드부터 진행한다. HEAD가 `a6e936fe2`인지 확인한다. 기존 gate worktree는 소스만 최신이고 build tree는 이전 버전이므로 최신 실행 근거로 쓰지 않는다.
3. 새 전용 Herdr Sonnet 세션에 빌드·실행을 위임한다. `justfile`/CUBRID_SSOT, server wrapper, 전용 포트 claim, `/tmp` 금지 규칙을 적용한다. CTP가 필요하면 컨테이너 `just ctp`와 명시 TC ref를 사용한다.
4. `auto_multidb_probe.py`의 K1 A→B→A 반례를 green으로 확인한다. `auto_multidb_watch_probe.py`는 아직 한 번도 실행하지 않았으므로 K2·두 DB 모두 IN_TRAN에서 B COMMIT 후 대기 A가 진행하고 기존 busy A가 보존되는지 검증한다. atomic 요청 전이 후 AutoCounter/AutoLoad 및 auth/TTL도 재검증한다.
5. 필요한 종료·취소·재시작/슬롯 복원 경합 검증과 남은 구현 범위를 처리한다. 정확성 통과 후 matched OFF/ON·기존 CAS 비교, 필요 시 기존 YCSB C/A 인프라로 비교하고 채택/보류/기각을 근거와 함께 결정한다. 최종 승인 재질문으로 멈추지 않는다.
6. 통합은 채택 근거가 확보된 후에 진행한다. 현재 `cas-merge`/기존 PR은 수정하지 않았다. 새 PR도 만들지 않았다.

### 보존 위치

- 엔진: `/home/cubrid/dev/worktrees/wf259-auto`, branch `codex/wf259-auto`, 최신 `a6e936fe2` 커밋·fork push 완료.
- 진단: `codex/wf259-auto-diag` (`2d0e7ed3c`), `codex/wf259-auto-lexer-fix` (`0229a588d`)도 fork push. 진단 trace를 제품 브랜치에 병합하지 않는다.
- 재검증 준비: `/home/cubrid/dev/worktrees/wf259-auto-final` (clean, 미빌드), `/home/cubrid/dev/worktrees/wf259-auto-gate` (기존 build tree 보존).
- 문서: `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/wf259-auto-design`, branch `design/wf259-auto-lifecycle`.
- 하네스: tooling `.git_ignored_dir/scratch/wf259-auto/`의 `AutoLoad.java`, `AutoCounter.java`, `auto_resume_probe.py`, `auto_multidb_probe.py`, `auto_multidb_watch_probe.py`, `STATUS.md`. AutoLoad는 `-Dwf259.prime=true`, 성능은 추가 `-Dwf259.warmupMillis=3000`, 외부 timeout 필수. 각 반복은 SELECT 2개이며 끝까지 논리 연결을 모두 유지한다.
- 설치/DB: 각 실행 작업 디렉터리와 `/home/cubrid/wf259ag-{od,rel}`, `/home/cubrid/wf259pool-{od,rel}`, `/home/cubrid/wf259pool2-{od,rel}`의 기존 설치·DB 보존. 런타임 로그에 기록된 소유 서버·브로커·master는 종료했고 claim도 반환했다.
- YCSB: tooling `.git_ignored_dir/scratch/wf-poc/runbook.md`, `env.sh`, `scripts/`; `/home/cubrid/dev/cubrid-perftools-internal/ycsb/ycsb/cubrid/run.sh`. 10M golden `/home/cubrid/wf125-ycsb-db/ycsb_g`는 불변으로 두고 전용 copydb 사본을 만든다. 다른 캠페인의 `/home/cubrid/wf-poc-db/ycsb`나 고정 포트/공용 properties를 변경하지 않는다. 과거 d533 측정값을 최신 기준선으로 대신 쓰지 않는다. 이 작업에서 YCSB는 아직 실행하지 않았다.
- 종료 기록: tooling `.git_ignored_dir/scratch/wf259-resume/active-worker.json`은 inactive. 최종 검증 준비 세션은 agent 시작 단계에서 `agent_pane_busy`로 실패했고 task prompt/build를 시작하지 않았다. 사용자 요청으로 종료·삭제했으며 task.json/server.log는 보존했다.

## 원시 근거

호스트 `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/herdr-integration/` 아래:

- `wf259-auto-base-1789303730/`: 최초 baseline과 `lead-review.md` 정정. 종료 연결을 파도처럼 처리한 초기 표는 채택 근거에서 제외했다.
- `wf259-auto-gate-1789305230/`: 최초 실패, prime 반례, bounded trace와 callback fix 11/11 근거.
- `wf259-auto-pool-1789309927/`: 양 모드 unit/smoke, 44/44, Flex 누수 전후, `pool-report-04.md`의 위 표와 로그, `pool-report-05.md` 배치 고정 비교, `edge-report.md` 인증/만료/갱신/다중 DB 반례.
- `wf259-auto-final-1789317487/`: 실행 미착수 준비 기록, `closed` 표시. 소유한 Herdr 작업 세션은 모두 종료·삭제했고 사용자의 default 세션은 보존했다.

새 회귀 TC의 testcase PR 추가는 QA 담당이다. 여기의 시험 시나리오·실패 및 수정 근거는 지도 최종 단일 test.md의 입력으로 인계한다.
