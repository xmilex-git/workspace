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
- release는 NDEBUG라 heap corruption이 silent SIGSEGV + 0-byte coredump → gdb attach batch로 스택 확보가 정석.
- resource_tracker(alloc/pgbuf) 누수 검출은 **CS(server) 모드 per-request에서만** 동작. SA(`csql -S`) selftest·bootless unit test는 누수를 못 잡는다 — selftest PASS인데 라이브 쿼리가 서버 크래시한 실사례. **라이브 검증은 반드시 CS 모드 debug 서버로.**
- 64bit libasan을 사용할 수 없는 환경에서는 ASAN 게이트를 **valgrind memcheck**(`--leak-check=full --track-origins=yes`)로 대체한다.
- 디버거 line-bp는 편집으로 라인이 밀리면 죽은 줄을 짚을 수 있다. 함수-bp 또는 **카운터(statdump)로 하네스-단언 가능하게** 만드는 편이 안전하다.

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

---

## 3. 환경·운영 — 착수 함정 목록

1. **stale 바이너리**: 검증 proof에 `cubrid_rel`(빌드 sha/timestamp) 기록. install sha == HEAD sha 확인.
2. **빌드는 `just build release|debug`만** (`WORKSPACE` 명시). raw cmake는 설치와 symlink 갱신을 누락하므로 사용하지 않는다. **debug + release 둘 다 풀빌드 green**이 기본 게이트다. 캠페인/브랜치 빌드는 공용 기본 설치본을 덮어쓰지 않도록 반드시 `just build <mode> <전용버전명>`으로 실행한다.
3. **재빌드·재설치가 conf를 리셋한다** — `stored_procedure`, `parallelism`, `max_parallel_workers`, `data_buffer_size` 등 필요한 설정을 빌드 후 다시 확인하고 적용한다.
4. **서버 제어는 `cubrid-server-ctl.sh` 래퍼만**. raw `cubrid server start|stop`은 파이프 hang. skill:cubrid-server-control 활용.
5. **`cubrid server stop <db>`는 master를 안 내린다** — 재빌드 바이너리가 포트 바인드 실패하면 stray `cub_master`부터 정리.
6. **kill-9된 서버는 master가 자동 재기동할 수 있다** — 재기동 후 프로세스와 환경이 검증 전제와 같은지 다시 확인한다.
7. **기능 env는 서버 프로세스 기준** — csql 클라이언트에만 설정한 env는 서버 동작을 바꾸지 않는다. 래퍼 호출 시 서버에 전달한다.
8. **debug 빌드에서 대형 DB 금지** — 대형 검증과 성능 측정은 release 빌드로 수행하고, debug는 FI·assert 검출과 소형 스모크에 사용한다.
9. 서브모듈(cubrid-cci)·untracked 결과 디렉토리는 건드리지 않는다. 작업 종료 시 **트리 원상복구 + 데몬(서버/master) 정리**.
10. **대화형 CUBRID 유틸리티를 stdin 없이 자동화에서 실행 금지** — EOF 입력으로 프롬프트가 반복되면 로그가 무한히 커져 디스크를 고갈시킬 수 있다. 응답을 명시적으로 전달하거나 비대화형 플래그를 사용하고, 자동화 로그에는 크기 상한과 디스크 여유 점검을 둔다. 전량 덤프보다 statdump 카운터·파일 크기 delta 같은 유계(bounded) 증거를 우선한다.
11. **공유 디스크 주의** — 대형 evidence, backup, DB는 생성 전에 예상 크기를 계산하고 상한을 둔다.
12. **인덱스 검증 쿼리는 sargable 술어 필수** — CUBRID는 인덱스 컬럼 조건(`col > 0` 등)이 없으면 인덱스를 사용하지 않을 수 있다. 인덱스 경로 검증은 (a) 인덱스 컬럼 술어 포함 쿼리와 (b) `;plan simple` 등 실제 인덱스 스캔 증거를 함께 확인한다.

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

- [ ] debug + release 풀빌드 green
- [ ] fail-before-fix 채증 → 수정 후 동일 방법 PASS
- [ ] CS 모드 debug 서버에서 라이브 실행(assert/crash/tracker leak 0)
- [ ] orphan-zero(정상/비정상 종료 + kill-9 후 임시파일 잔존 0)
- [ ] 트리 원상복구 + 데몬 정리 + proof에 `cubrid_rel` 기록
