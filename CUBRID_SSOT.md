# CUBRID 개발·테스트 SSOT

## 1. 정확성 판정 — 주로 하는 실수

### 실수 1: raw 출력 md5로 오답을 "판정"한다 → 금지
- `raw-stdout | md5sum`, `MD5(GROUP_CONCAT())` 차이를 corruption 증거로 삼으면 행 순서/포맷 차이를 실제 결함으로 오판할 수 있다.
- parity.sh 계열은 `;trace on`/`;plan detail` 라인이 결과행으로 섞여 md5가 timing 차이로 불일치하는 위양성도 발생한다.
- **규칙**: 판정은 **robust 집계만** — `COUNT / SUM(CAST … AS NUMERIC(38,0)) / MIN / MAX` + 터미널 페이지 포함. 결과행 grep은 순수 데이터행만.

### 실수 2: "serial == parallel 통과"가 사실은 둘 다 serial이었다 (passthrough-tautology)
- `parallelism=1`만 내려도 병렬 sort는 `max_parallel_workers`로 여전히 8워커 병렬. **serial 강제는 `parallelism=1` AND `max_parallel_workers=1` 둘 다** 필요.
- 반대로 `COUNT(*) FROM (SELECT DISTINCT …)` 같은 aggregate-wrapper는 옵티마이저가 내부 연산자를 조용히 serial화한다. inner `ORDER BY`는 통째로 drop되기도 한다(정렬 검증엔 DISTINCT나 순서-민감 consumer 사용).
- **규칙**: 병렬이 실제로 걸렸는지 `;trace on`의 `parallel workers: N>1`로 **실증**한다(`;plan detail`엔 안 나옴). 신규 경로 검증은 해당 경로가 실제로 실행됐다는 별도 증거를 함께 확인한다. 구경로로 폴백해도 parity 자체는 PASS할 수 있다.
- 레거시 어댑터만 통과시키는 게이트는 신규 코드를 전혀 검증하지 못한다 — 신 구조를 **합성 입력으로 강제 생성**해 forward/reverse/jump/empty/terminal 경계까지 검증.

### 실수 3: 집계 parity만 보고 "클라이언트에 안 보이는" 결함을 놓친다
- 서버 내부 집계가 정상이어도 클라이언트 전송 경로에서 실제 행이 누락될 수 있으므로 집계-기반 하네스만으로는 충분하지 않다.
- 1:1 조인 + 한쪽 집계에서는 hash match miss가 결과 집계에 드러나지 않을 수 있다.
- **규칙**: top-level SELECT(ORDER BY/DISTINCT/GROUP BY)의 **실제 행 반환**을 게이트에 포함. 조인 검증엔 **readkeys(match율) 동반 확인**. 클라이언트 fetch/캐시/holdable 싱크는 별도 e2e로.

### 실수 4: 비결정 race를 단회 PASS로 무죄 판정한다
- 단회 PASS(위음성)만으로 비결정 회귀를 무죄 판정하면 안 된다. 원인 귀속은 반복 재현과 bisect 등으로 확인한다.
- **규칙**: race 판별은 **반복 N회**(FAIL 재현도 PASS 판정도). 병렬 소비를 신설하면 **공유 mutable 상태(커서/버퍼/scratch) 감사**를 착지 전에 수행 — 검증이 race를 발현 못 시키면 latent로 통과한다.

### 실수 5: fail-before-fix 없이 수정하고, 오진을 그대로 둔다
- **규칙**: 수정 전 실패를 먼저 재현·채증(fail-before-fix)하고, 수정 후 같은 방법으로 PASS를 확인한다. fault-injection(ENOSPC/OOM selftest)도 같은 원칙.
- 루트코즈 오판이 확인되면 정정을 명시적으로 기록(supersede)한다. 역사 재작성보다 후속 작업자가 틀린 결론을 재사용하지 않게 하는 것이 중요하다.
- 이론적 레이스/창 지적은 곧 구현 과제가 아니다. 수정 전에 도달 가능성을 검증한다.

### 실수 6: 검증 수단의 한계를 모른 채 "clean"을 선언한다
- release 빌드는 `er_log_debug`가 no-op → release 로그로 신경로 발동 실증 불가(debug 로그 또는 카운터로).
- release는 NDEBUG라 heap corruption이 silent SIGSEGV + 0-byte coredump → ~~gdb attach batch로 스택 확보~~ (2026-08-06 supersede: 라이브 gdb attach 금지 — 아래 gdb 배제 규칙 참조. 코어 파일 오프라인 판독은 허용).
- resource_tracker(alloc/pgbuf) 누수 검출은 **CS(server) 모드 per-request에서만** 동작. SA(`csql -S`) selftest·bootless unit test는 누수를 못 잡는다 — selftest PASS인데 라이브 쿼리가 서버 크래시한 실사례. **라이브 검증은 반드시 CS 모드 optdebug 서버로.**
- 64bit libasan을 사용할 수 없는 환경에서는 ASAN 게이트를 **valgrind memcheck**(`--leak-check=full --track-origins=yes`)로 대체한다.
- 디버거 line-bp는 편집으로 라인이 밀리면 죽은 줄을 짚을 수 있다. 함수-bp 또는 **카운터(statdump)로 하네스-단언 가능하게** 만드는 편이 안전하다.
- **(2026-08-06) gdb를 이용한 검증은 전면 배제한다** — 라이브 서버 attach·함수-bp 경로 실증 포함. gdb attach 세션이 서버 코어 덤프를 유발한 인시던트(CBRD-27181 QA 중 core.cub_server 생성). 코드 경로 발동 실증은 **perf 심볼 밴드**(해당 경로 유발 질의 루프 중 `perf record -p <pid>` 후 심볼 존재/부재 확인), 카운터, 차등 A/B 출력으로 한다.

---

## 2. 측정(perf) — 주로 하는 실수

### 실수 7: 오염된 측정으로 구조 결론을 내린다
- cold-cache, 직전 run의 config 로드 오류, **PATH 오염**이 겹치면 구조적 성능 차이로 오판할 수 있다.
- **규칙**: `env -i` 격리 + warmup 후 median N회(예: warmup 2 + median 5) + 양측 동일 conf/빌드타입(CMakeCache로 확인)을 갖춘 뒤에만 비교. 비교 대상 파라미터 공정성(예: sort_buffer_size vs work_mem effective 값)을 paramdump로 확인.
- **측정·parity 실행 중 `just build` 병행 금지** — 빌드가 `~/CUBRID` 심링크를 repoint해 공용 master와 포트 충돌(실제 인시던트).
- 에러로 중단된 run의 시간은 무효치다(perf 표에 넣지 말 것).

### 실수 8: perf 회귀 원인을 가정으로 찍는다
- **규칙**: 원인 귀속은 프로파일(VTune/strace 파일별 분해)과 반증 실험(해당 요소 on/off)으로 확정한다. 신규 코드의 영향은 변경 경로를 비활성화한 대조군과 비교하고, CoV(≤15%) 없는 median은 신뢰하지 않는다.
- valgrind/VTune/스트레스는 검증 쿼리 순간에만 attach — 적재·픽스처 준비는 일반 서버로. 10분+ 명령은 background로.

### 실수 9: 게이트 마진을 관측 분산과 무관하게 고정하고, FAIL을 회귀 실재의 증거로 쓴다
- 2026-07-24 PR#7504 최소브랜치 게이트 실사례: 사전 고정 "median ≤ +3% AND 패배 < 6/8"인데 실측 per-run CoV 8.7%, paired sd 14.0pp → paired median 부트스트랩 95% CI가 −1.05%..+14.42%(0 포함), 패배축 단독 false-FAIL 확률 0.145. 같은 분산에서 3pp를 판별하려면 약 171쌍이 필요했다. **검정력 없는 FAIL은 merge 보류의 근거는 되지만 "회귀 실재"의 근거가 아니다** — 그 위에 커밋 단위 귀속을 세우면 없는 효과를 추적한다.
- **규칙**: 게이트를 고정하기 전에 (a) 예비 런으로 per-run CoV·paired sd를 실측하고 (b) 그 분산에서 마진을 판별할 쌍 수를 계산한다. 긍정(비열등) 판정에는 부트스트랩 CI 상한 ≤ 마진을 요구한다. 패배 카운트 축은 부호검정이므로 마진과 무관하게 "작은 양의 효과"를 잡는다는 점을 명시한다.

### 실수 10: 대용량 인덱스 빌드 측정에서 wall-clock 분산의 지배 변수를 오해한다
- 20G/341M행 CREATE INDEX의 런시간은 **정렬 temp 쓰기가 OS page cache에 흡수되는지 여부**가 지배한다(temp 볼륨은 런 종료 시 unlink되므로, 캐시 여유가 있으면 writeback 없이 사라진다). 데이터 볼륨 22.9GiB를 prewarm으로 선점하자 동일 워크로드가 **110s → 365s**, 프로세스 실기록 **~1.2GB → 119GB**로 전환됐다(2026-07-25 실측, `sda` %util 98%).
- 따라서 "캐시를 채워 분산을 줄인다"는 직관은 여기서 역효과다. cold/warm 어느 쪽으로도 강제하지 말고, 캠페인 내 순서균형(AB/BA)으로 대칭만 확보한 뒤 **레짐이 다른 캠페인 간 수치는 풀링하지 않는다**.
- **작업량 대조는 wall-clock보다 해상도가 높다**: release에서도 항상 기록되는 page-buffer victim flush 알림("Flush victim candidates ... finished (count: N)")을 timed 창구간으로 합산하면 서버가 볼륨에 내려보낸 페이지 수를 오버헤드 0으로 얻는다(레인간 0.2% 해상도 실증). `cubrid statdump`의 `Num_*`는 **perfmon watcher가 붙어 있을 때만** 누적되므로(`perfmon_add_stat` → `perfmon_is_perf_tracking`) watcher 없이 뜬 서버에서는 전부 0이다 — 카운터가 0이면 "일을 안 한 것"이 아니라 "수집이 꺼진 것"이다.

---

## 3. 환경·운영 — 착수 함정 목록

1. **stale 바이너리**: 검증 proof에 `cubrid_rel`(빌드 sha/timestamp) 기록. install sha == HEAD sha 확인.
2. **빌드는 `just build release|debug`만** (`WORKSPACE` 명시). raw cmake는 설치와 symlink 갱신을 누락하므로 사용하지 않는다. **(2026-07-22) plain debug 빌드 금지 — justfile이 mode `debug`를 `optdebug` preset으로 리맵한다(설치처 `~/optdebug/`). assert/FI 검증도 optdebug로 수행한다.** **optdebug + release 둘 다 풀빌드 green**이 기본 게이트다. 캠페인/브랜치 빌드는 공용 기본 설치본을 덮어쓰지 않도록 반드시 `just build <mode> <전용버전명>`으로 실행한다.
3. **재빌드·재설치가 conf를 리셋한다** — `stored_procedure`, `parallelism`, `max_parallel_workers`, `data_buffer_size` 등 필요한 설정을 빌드 후 다시 확인하고 적용한다.
4. **서버 제어는 `cubrid-server-ctl.sh` 래퍼만**. raw `cubrid server start|stop`은 파이프 hang. skill:cubrid-server-control 활용.
5. **`cubrid server stop <db>`는 master를 안 내린다** — 재빌드 바이너리가 포트 바인드 실패하면 stray `cub_master`부터 정리.
6. **kill-9된 서버는 master가 자동 재기동할 수 있다** — 재기동 후 프로세스와 환경이 검증 전제와 같은지 다시 확인한다.
7. **기능 env는 서버 프로세스 기준** — csql 클라이언트에만 설정한 env는 서버 동작을 바꾸지 않는다. 래퍼 호출 시 서버에 전달한다.
8. **optdebug 빌드에서 대형 DB 금지** — 대형 검증과 성능 측정은 release 빌드로 수행하고, optdebug는 FI·assert 검출과 소형 스모크에 사용한다.
9. 서브모듈(cubrid-cci)·untracked 결과 디렉토리는 건드리지 않는다. 작업 종료 시 **트리 원상복구 + 데몬(서버/master) 정리**.
10. **대화형 CUBRID 유틸리티를 stdin 없이 자동화에서 실행 금지** — EOF 입력으로 프롬프트가 반복되면 로그가 무한히 커져 디스크를 고갈시킬 수 있다. 응답을 명시적으로 전달하거나 비대화형 플래그를 사용하고, 자동화 로그에는 크기 상한과 디스크 여유 점검을 둔다. 전량 덤프보다 statdump 카운터·파일 크기 delta 같은 유계(bounded) 증거를 우선한다.
11. **공유 디스크 주의** — 대형 evidence, backup, DB는 생성 전에 예상 크기를 계산하고 상한을 둔다.
12. **인덱스 검증 쿼리는 sargable 술어 필수** — CUBRID는 인덱스 컬럼 조건(`col > 0` 등)이 없으면 인덱스를 사용하지 않을 수 있다. 인덱스 경로 검증은 (a) 인덱스 컬럼 술어 포함 쿼리와 (b) `;plan simple` 등 실제 인덱스 스캔 증거를 함께 확인한다.
13. **(2026-08-06) 장기 백그라운드 작업은 `nohup`/`setsid` 금지 — tmux 세션을 할당해 그 안에서 실행한다.** agent shell에서 `nohup …&`/`setsid …&`로 띄운 TC 재현·빌드가 launcher 호출 종료 직후 **소리 없이 죽는** 인시던트 2회(출력 0바이트, 프로세스 부재, 에러 없음). 같은 호출 안에 `sleep`을 넣어 자식을 안착시키는 우회는 비결정적이라 금지. 정석: `tmux new-session -d -s <name> '<cmd>'`로 실행하고 `tmux capture-pane`/로그 파일로 폴링, 종료 후 `tmux kill-session`. 완료 판정은 프로세스 부재가 아니라 **결과 파일/로그의 종료 마커**로 한다.
14. **(2026-08-07) 대용량 DB를 새로 적재할 땐 인덱스 단계를 분리해 loaddb `--no-logging-index`로 태운다** (PR #7504 / CBRD-27071, develop `1aa79a03b`). 스키마(인덱스 제외) → 데이터 → **인덱스 파일** 3단계로 나누고 마지막 단계만 `cubrid loaddb -i <index.sql> --no-logging-index <db>`로 적재하면 no-redo 병렬 벌크 빌드가 발화한다(341M행 기준 609.2s → 245.5s, 2.48×). 발화 조건이 좁다: **서버가 떠 있는 CS 모드**여야 하고(SA 모드는 플래그를 무시한다 — `load_db.c:842`), 서버가 loaddb 계열 client type의 요청만 허용하며(`network_interface_sr.cpp:4729`), `-i` 인덱스 로드 구간에만 적용된다. PK/FK를 `-s` 스키마 파일에 남겨두면 이 경로를 타지 못하고 데이터 적재 중 인덱스 유지 비용까지 그대로 낸다. WITH ONLINE 인덱스와 정렬 런이 부족한 소형 테이블은 옵션과 무관하게 기존 로깅 빌드로 폴백한다. **적재 후에는 전체 백업을 새로 받는다** — 로그 체인에 barrier가 남아 이전 백업 체인으로는 그 지점을 넘는 replay가 거부된다(`log_recovery.c:3272`).

---

## 4. 코드 작업 규칙

1. **착수·커밋 전 `git fetch --all` + rebase** — 브랜치 명시 없는 단순 fetch는 동시 착지를 놓칠 수 있다. 문서의 파일:라인 좌표는 **HEAD에서 re-ground**한다.
2. **cross-thread private-heap 금지**: 워커가 `db_private_alloc`(스레드별 mspace)한 것을 리더가 `db_private_free`하면 힙이 손상된다. 공유 배열은 리더가 할당하고 워커는 채우기만 한다.
3. **PEEK(borrowed) 포인터를 free/realloc하지 말 것**: PEEK 리더는 페이지 내부 포인터를 빌려준다. 소비자가 free할 경로면 COPY(peek=0) 필수다.
4. **실패를 삼키는 API 금지(silent truncation)**: close/flush/freeze 실패는 latch하고 이후 사용 지점에서 에러를 올린다. OOM 경로도 소유권 이전 **전에** 실패 처리한다.
5. 새 소스 파일은 **server/SA 양쪽 CMakeLists에 등록**한다.

---

## 5. 문서·프로세스 거버넌스

1. 세션 시작 시 SSOT의 현재 규칙과 이미 폐기된 결론을 먼저 확인한다.
2. 실패한 가설과 시도는 재진입하지 않도록 기록하고, 결론이 바뀌면 기존 기록을 supersede한다.
3. **문서 역할 분리**: SSOT에는 현재 결론과 방향을 두고, evidence에는 근거와 측정을 둔다. 사실이 바뀌면 SSOT 본문을 수정하고 폐기된 결론은 명시적으로 supersede한다.
4. **구현 이슈는 자족적으로**: 좌표 + 재현 절차 + 기계적 수용 기준, [CONFIRMED]/[VERIFY] 구분. 실행자가 SSOT 없이도 착수 가능해야 한다.
5. **완료 보고의 범위를 부풀리지 않는다**: "parity green"이 실제로 무엇을 검증했는지(serial==parallel 정합성일 뿐 develop 대비 perf가 아님, 프록시 검증일 뿐 실물 경로가 아님) 명시. 부분 통과를 통과로 쓰면 나중에 정정 비용이 더 크다.
6. 변경 단위별로 커밋 → push → 이슈 보고 → evidence 기록 → 실패·오진 정정 순서를 지킨다. SSOT는 사실이 바뀔 때만 갱신한다.
7. "환경 결함으로 검증 미완 close" 금지 — 런타임 검증은 필수 게이트다.

---

## 6. 최소 검증 체크리스트 (신규 경로/수정 착지 시)

- [ ] optdebug + release 풀빌드 green
- [ ] fail-before-fix 채증 → 수정 후 동일 방법 PASS
- [ ] CS 모드 optdebug 서버에서 라이브 실행(assert/crash/tracker leak 0)
- [ ] orphan-zero(정상/비정상 종료 + kill-9 후 임시파일 잔존 0)
- [ ] 트리 원상복구 + 데몬 정리 + proof에 `cubrid_rel` 기록

---

## 7. GJC/하네스 메모리 및 결과 전달 규칙

### 7.1 OOM 종류를 분리해 진단한다

- `CONSTRAINT_MEMCG`와 `Killed process`가 kernel 로그에 있으면 컨테이너 memory cgroup OOM이다. `RangeError: Out of memory`와 exit status 1만 있고 signal 9/kernel OOM 기록이 없으면 Bun/JSC 또는 하네스 내부의 주소공간·할당 실패로 분류한다.
- 원격 rootless Podman의 cgroups v1 환경에서는 rootless user manager에 memory controller delegation이 없을 수 있다. `systemd-run --user --property=MemoryMax/MemoryLimit`의 표시값만으로 실제 cgroup 제한이 적용됐다고 선언하지 말고, `/proc/<pid>/cgroup`와 해당 memory controller의 실제 limit을 검증한다.
- 진짜 cgroup 제한이 확인되지 않으면 이를 명시적으로 보고한다. 주소공간 제한(`RLIMIT_AS`)은 RSS 제한이 아닌 fallback guard다.

### 7.2 GJC 실행 메모리와 병렬성

- GJC의 task/subagent는 별도 프로세스가 아니라 동일 Bun 프로세스와 heap에서 실행될 수 있다. 병렬·team·background subagent를 기본값으로 사용하지 말고, 장시간 검증은 순차·유계 실행으로 운영한다. 불가피한 경우에도 동시에 하나만 실행한다.
- 원격에서 확인된 Bun/GJC의 20GiB `ulimit -v`는 allocator/JSC 예약만으로 정상 세션을 죽일 수 있으므로 사용하지 않는다. 진짜 cgroup delegation이 없는 동안에는 64GiB `RLIMIT_AS`를 임시 fallback으로 사용하고, RSS가 약 40GiB에 접근하면 추가 작업을 중단하고 짧은 상태 파일을 디스크에 남긴다. 이는 20GiB cgroup이 아니며, 실제 RSS 보호를 보장하지 않는다.
- 동일 대화·checkout·DB·포트에 GJC를 중복 실행하지 않는다. 새 세션을 띄우기 전에 GJC PID, tmux pane, server/master, DB/port ownership을 확인한다. `1gjc` sentinel과 관계없는 사용자/notify/claude 세션은 건드리지 않는다.
- GJC 재개 후에는 `/proc/<pid>/status`의 `VmRSS/VmSize`, `/proc/<pid>/limits`, cgroup 경로, kernel OOM 로그를 확인해 guard와 실제 상태를 검증한다. 화면의 `Working`/`done`만으로 안전성이나 완료를 선언하지 않는다.

### 7.3 결과·로그·임시 파일의 디스크 전달

- 결과, 다운로드, evidence, command log, scratch는 반드시 tooling repo의 git-ignored 디스크 경로인 `.git_ignored_dir/scratch/`와 그 하위 디렉터리에 직접 저장한다. `/tmp`, `/var/tmp`, 상속된 `$TMPDIR`에 대형 결과를 저장하지 않는다.
- `TMPDIR`, `TMP`, `TEMP`는 명시적인 디스크 경로로 지정한다. `TMUX_TMPDIR`은 결과 저장 경로가 아니다. 외부 tmux server의 ownership/visibility를 깨뜨릴 수 있으므로 임의로 디스크 scratch로 바꾸지 말고, runtime socket과 결과 파일을 구분한다.
- 대형 결과·JSONL·로그·artifact를 GJC 컨텍스트에 직접 열거나 `Read artifact://...`, `@` 첨부로 가져오지 않는다. 파일은 디스크에 남기고 GJC에는 경로, 크기, checksum, exit code, 유계 요약만 전달한다.
- 명령 stdout은 파일로 redirect하고, 대화에는 필요한 짧은 tail·summary만 넣는다. 파일 크기와 출력 상한을 먼저 정하고 무제한 `cat`/전체 로그 import를 하지 않는다.

### 7.4 하네스 도구별 유계 실행

- `find`는 명시적인 작은 경로와 modest `limit`을 사용한다. 넓은 tree를 검색할 때는 결과 수와 출력 바이트를 별도로 제한한다.
- `find` progress callback이 매 tick마다 누적 배열을 `slice/join`하지 않는지 확인한다. `find` 자체가 작은 결과를 반환해도 이미 주소공간 ceiling에 도달한 프로세스에서는 progress callback의 작은 할당이 uncaught `RangeError`를 일으킬 수 있다.
- progress/render callback의 할당 실패가 전체 GJC 프로세스를 종료시키지 않도록 upstream 수정 여부를 추적한다. 수정 전에는 bounded reproducer와 stack trace를 확보하고, 대규모 메모리 할당으로 재현하지 않는다.
- 저장된 세션·artifact의 전체 크기가 작다는 사실만으로 live heap의 일시적 폭증을 배제하지 않는다. persisted state와 in-process subagent/tool-output retention을 별도로 측정한다.

### 7.5 조사·재개 완료 기준

- OOM 조사는 kernel evidence, process RSS/VAS, cgroup 실제 limit, GJC crash stack, session/tool-log 크기를 각각 확인하고, 확정 사실·추정 원인·배제 가설을 분리해 디스크 보고서로 남긴다.
- 재개 prompt에는 조사 보고서 경로, remaining scope, sequential/bounded 규칙, 결과 디스크 경로, 메모리 중단 기준, resource ownership, 검증 명령을 명시한다.
- 조사 결과와 재개 prompt가 디스크에 존재하는 것을 확인한 뒤 GJC를 띄운다. launch 후에는 새 tmux session/pane, 실제 GJC PID/cwd, session identity, memory guard, 현재 RSS/VAS, readiness, 새 OOM 부재를 확인한다.
