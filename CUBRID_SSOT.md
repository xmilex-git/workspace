# CUBRID 개발·테스트 SSOT — 주로 하는 실수와 지켜야 할 규칙

## 1. 정확성 판정 — 주로 하는 실수

### 실수 1: raw 출력 md5로 오답을 "판정"한다 → 금지
- `raw-stdout | md5sum`, `MD5(GROUP_CONCAT())` 차이를 corruption 증거로 삼았다가 **정상 병렬 코드를 여러 번 revert**한 이력이 있다(FAIL-05/FAIL-08, ~10시간 손실). 행 순서/포맷 아티팩트일 뿐이었다.
- parity.sh 계열은 `;trace on`/`;plan detail` 라인이 결과행으로 섞여 md5가 timing 차이로 불일치하는 위양성도 실재(I-16(d), J-2).
- **규칙**: 판정은 **robust 집계만** — `COUNT / SUM(CAST … AS NUMERIC(38,0)) / MIN / MAX` + 터미널 페이지 포함. 결과행 grep은 순수 데이터행만.

### 실수 2: "serial == parallel 통과"가 사실은 둘 다 serial이었다 (passthrough-tautology)
- `parallelism=1`만 내려도 병렬 sort는 `max_parallel_workers`로 여전히 8워커 병렬. **serial 강제는 `parallelism=1` AND `max_parallel_workers=1` 둘 다** 필요.
- 반대로 `COUNT(*) FROM (SELECT DISTINCT …)` 같은 aggregate-wrapper는 옵티마이저가 내부 연산자를 조용히 serial화한다. inner `ORDER BY`는 통째로 drop되기도 한다(정렬 검증엔 DISTINCT나 순서-민감 consumer 사용).
- **규칙**: 병렬이 실제로 걸렸는지 `;trace on`의 `parallel workers: N>1`로 **실증**한다(`;plan detail`엔 안 나옴). 신규 경로(게이트) 검증은 **engagement 카운터 delta**(예: `Num_qfile_new_backed_create`)를 함께 확인 — 게이트가 거부돼 구경로 폴백이어도 parity는 PASS하기 때문.
- 레거시 어댑터만 통과시키는 게이트는 신규 코드를 전혀 검증하지 못한다 — 신 구조를 **합성 입력으로 강제 생성**해 forward/reverse/jump/empty/terminal 경계까지 검증.

### 실수 3: 집계 parity만 보고 "클라이언트에 안 보이는" 결함을 놓친다
- frozen NEW 리스트가 클라이언트 전송 경로에서 **0행**을 반환하는 CRITICAL(R1)을 집계-기반 하네스가 전혀 못 봤다. 서버 내부 집계는 정상이었기 때문.
- 1:1 조인 + 한쪽 집계에서는 hash match 95% miss도 md5에 불가시(LEFT-outer 허위 안전, K-12).
- **규칙**: top-level SELECT(ORDER BY/DISTINCT/GROUP BY)의 **실제 행 반환**을 게이트에 포함. 조인 검증엔 **readkeys(match율) 동반 확인**. 클라이언트 fetch/캐시/holdable 싱크는 별도 e2e로.

### 실수 4: 비결정 race를 단회 PASS로 무죄 판정한다
- 단회 PASS(위음성)를 근거로 회귀를 upstream merge에 오귀속했다가, bisect로 진범(자기 커밋의 공유 커서 race)이 밝혀진 사례(K-12).
- **규칙**: race 판별은 **반복 N회**(FAIL 재현도 PASS 판정도). 병렬 소비를 신설하면 **공유 mutable 상태(커서/버퍼/scratch) 감사**를 착지 전에 수행 — 검증이 race를 발현 못 시키면 latent로 통과한다.

### 실수 5: fail-before-fix 없이 수정하고, 오진을 그대로 둔다
- **규칙**: 수정 전 실패를 먼저 재현·채증(fail-before-fix)하고, 수정 후 같은 방법으로 PASS를 확인한다. fault-injection(ENOSPC/OOM selftest)도 같은 원칙.
- **"오진도 확정 기록을 이긴다"**: 루트코즈 오판(#99, #120a, #127)이 확인되면 정정을 명시적으로 기록(supersede)한다. 역사 재작성 금지 — 틀린 결론 위에 다음 작업자가 쌓는 것이 최악.
- 이론적 레이스/창 지적(리뷰 R계열)은 곧 구현 과제가 아니다 — **도달가능성 검증부터**(P12). 제안된 수정이 데드락 유발/무효로 판명된 이력이 있다.

### 실수 6: 검증 수단의 한계를 모른 채 "clean"을 선언한다
- release 빌드는 `er_log_debug`가 no-op → release 로그로 신경로 발동 실증 불가(debug 로그 또는 카운터로).
- release는 NDEBUG라 heap corruption이 silent SIGSEGV + 0-byte coredump → gdb attach batch로 스택 확보가 정석.
- resource_tracker(alloc/pgbuf) 누수 검출은 **CS(server) 모드 per-request에서만** 동작. SA(`csql -S`) selftest·bootless unit test는 누수를 못 잡는다 — selftest PASS인데 라이브 쿼리가 서버 크래시한 실사례. **라이브 검증은 반드시 CS 모드 debug 서버로.**
- 이 호스트엔 64bit libasan이 없다 → ASAN 게이트는 **valgrind memcheck**(`--leak-check=full --track-origins=yes`)로 대체.
- 디버거 line-bp는 자기 편집으로 라인이 밀리면 죽은 줄을 짚는다(stale bp로 오판한 사례 K-10) — 함수-bp 또는 **카운터(statdump)로 하네스-단언 가능하게** 만드는 것이 정공법.

---

## 2. 측정(perf) — 주로 하는 실수

### 실수 7: 오염된 측정으로 구조 결론을 내린다
- cold-cache + 직전 run의 config 로드 오류 + **PATH 오염(develop csql이 redesign conf를 로드)** 이 겹쳐 "tree-wide single-thread 갭"이라는 오판을 낳은 사례(I-18(f)).
- **규칙**: `env -i` 격리 + warmup 후 median N회(예: warmup 2 + median 5) + 양측 동일 conf/빌드타입(CMakeCache로 확인)을 갖춘 뒤에만 비교. 비교 대상 파라미터 공정성(예: sort_buffer_size vs work_mem effective 값)을 paramdump로 확인.
- **측정·parity 실행 중 `just build` 병행 금지** — 빌드가 `~/CUBRID` 심링크를 repoint해 공용 master와 포트 충돌(실제 인시던트).
- 에러로 중단된 run의 시간은 무효치다(perf 표에 넣지 말 것).

### 실수 8: perf 회귀 원인을 가정으로 찍는다
- TDE/merge-copy/mixed-backing을 차례로 의심했으나 VTune에서 전부 0.0s 기각 — 실제는 per-tuple 락(FAIL-07). 회귀가 신규 코드 탓인지도 **env-OFF(구경로)와 대조**해야 안다(구경로도 느리면 tree-wide).
- **규칙**: 원인 귀속은 프로파일(VTune/strace 파일별 분해)로 핀 박고, 반증 실험(해당 요소 on/off)으로 확정한다. CoV(≤15%) 없는 median은 신뢰하지 않는다.
- valgrind/VTune/스트레스는 검증 쿼리 순간에만 attach — 적재·픽스처 준비는 일반 서버로. 10분+ 명령은 background로.

---

## 3. 환경·운영 — 착수 함정 목록

1. **stale 바이너리**: 검증 proof에 `cubrid_rel`(빌드 sha/timestamp) 기록. install sha == HEAD sha 확인.
2. **빌드는 `just build release|debug`만** (`WORKSPACE` 명시). raw cmake 금지(설치/symlink 안 됨). **debug + release 둘 다 풀빌드 green**이 기본 게이트.
3. **재빌드·재설치가 conf를 리셋한다** — `stored_procedure=no`뿐 아니라 `parallelism/max_parallel_workers/data_buffer_size` 전부. **매 빌드 후 `just conf` 재적용**(PL 부팅 실패·엉뚱한 측정의 단골 원인). 캠페인 파라미터의 정본은 workspace repo 루트의 `cubrid.conf` — 파라미터 변경은 그 파일을 편집하고 `just conf`로 반영.
4. **서버 제어는 `cubrid-server-ctl.sh` 래퍼만**. raw `cubrid server start|stop`은 파이프 hang. skill:cubrid-server-control 활용.
5. **`cubrid server stop <db>`는 master를 안 내린다** — 재빌드 바이너리가 포트 바인드 실패하면 stray `cub_master`부터 정리.
6. **kill-9된 서버는 master가 자동 재기동하며 게이트 env를 상속하지 않는다** — 재기동 후 env 전제가 조용히 무효화됨.
7. **게이트/기능 env는 서버 프로세스 기준** — csql 클라이언트 env는 무효. 래퍼 호출 시 env로 전달.
8. **debug 빌드에서 대형 DB(tpch_sf10, 60M행) 금지** — 메모리 과다. debug 검증은 소형(wmloc 4.19M)/TDE(wmg003), 대형은 release 전용.
9. fresh 빌드에서 PL(Java SP) 서버 부팅 실패는 기지 이슈 — `stored_procedure=no` 우회(쿼리 테스트 무영향). 자기 변경 탓으로 오귀속하지 말 것.
10. 서브모듈(cubrid-cci)·untracked 결과 디렉토리는 건드리지 않는다. 작업 종료 시 **트리 원상복구 + 데몬(서버/master) 정리**.

---

## 4. 코드 작업 규칙

1. **착수·커밋 전 `git fetch --all` + rebase** — 브랜치 명시 없는 단순 fetch가 동시 착지를 놓친 실사고 있음. 문서의 파일:라인 좌표는 **HEAD에서 re-ground**(라인 드리프트).
2. **소유권 계약을 확장 없이 필드만 추가하지 말 것**: `QFILE_LIST_ID`류 구조에 자원을 더하면 copy/clear/MOVE·SKIP·PROHIBIT 모드 전부에 소유권 처리를 확장해야 한다. 누락 = 경로별 leak 또는 double-free.
3. **cross-thread private-heap 금지**: 워커가 `db_private_alloc`(스레드별 mspace)한 것을 리더가 `db_private_free`하면 힙손상 ABORT(#109). 공유 배열은 리더가 할당, 워커는 채우기만.
4. **PEEK(borrowed) 포인터를 free/realloc하지 말 것**: PEEK 리더는 페이지 내부 포인터를 빌려준다. 소비자가 free할 경로면 COPY(peek=0) 필수. `size==0→alloc` 가드 누락류 힙오염 다발 지점.
5. **실패를 삼키는 API 금지(silent truncation)**: close/flush/freeze 실패는 latch하고 이후 사용 지점(scan-open 등 단일 choke point)에서 에러 raise. `(void) ret`로 버리면 ENOSPC가 무음 0행이 된다. OOM 경로(noexcept-new NULL 포함)도 소유권 이전 **전에** 실패 처리.
6. **자원 해제 지점보다 앞에서 강제하지 말 것 / 뒤에서 참조하지 말 것**: serial 강제는 워커풀 예약 이전에(예약 후 강제 = tracker leak assert), destroy는 활성 reader/scan close 이후에.
7. 새 소스 파일은 **server/SA 양쪽 CMakeLists에 등록**(한쪽 누락 = undefined ref).
8. 게이트 스크립트의 `grep`은 실패 출력의 실제 토큰 포맷에만 매칭(테스트 이름에 키워드가 들어가 오탐한 사례). 테스트 이름에 게이트 키워드 금지.
9. 신규 경로는 **env 게이트(기본 OFF)로 착지**하고, 구경로(env-OFF) 무회귀를 별도 확인. 기본 ON 전환은 full-suite 통과 후 별도 결정(사람 승인).
10. 근본 기판이 삭제 예정인 pre-existing 버그는 근본 수정 대신 **가드(직렬 강등 등) + 삭제 체크리스트 이관** — 단 가드 제거 항목을 반드시 체크리스트에 등재.

---

## 5. 문서·프로세스 거버넌스

1. **세션 시작 시 SSOT(현재 상태 + DO-NOT-REASSUME)를 먼저 읽는다.** 접근이 오염 전제 목록과 충돌하면 멈추고 보고.
2. **새 시도 전에 실패 가설 대장(FAILED-ATTEMPTS LEDGER)을 먼저 읽는다** — 같은 막다른 길(DO NOT REPEAT) 재진입 방지. 대장은 append-only, 폐기는 supersede로.
3. **문서 역할 분리**: SSOT = 결론/방향(append 금지, 사실이 바뀌면 본문 수정), evidence = 근거/측정(append). 폐기된 결론은 DO-NOT-REASSUME에 흡수. GitHub 이슈 본문이 정본이면 로컬 미러 동기화까지가 한 세트.
4. **구현 이슈는 자족적으로**: 좌표 + 재현 절차 + 기계적 수용 기준, [CONFIRMED]/[VERIFY] 구분. 실행자가 SSOT 없이도 착수 가능해야 한다.
5. **완료 보고의 범위를 부풀리지 않는다**: "parity green"이 실제로 무엇을 검증했는지(serial==parallel 정합성일 뿐 develop 대비 perf가 아님, 프록시 검증일 뿐 실물 경로가 아님) 명시. 부분 통과를 통과로 쓰면 나중에 정정 비용이 더 크다.
6. 슬라이스 단위 거버넌스: 커밋(태그 규약) → push → 이슈에 보고 → evidence 기록 → 실패/오진 정정 → (사실 변경 시만) SSOT 갱신.
7. "환경 결함으로 검증 미완 close" 금지 — 런타임 검증은 필수 게이트다.

---

## 6. 최소 검증 체크리스트 (신규 경로/수정 착지 시)

- [ ] debug + release 풀빌드 green
- [ ] fail-before-fix 채증 → 수정 후 동일 방법 PASS
- [ ] robust 집계 parity: serial(`parallelism=1` AND `max_parallel_workers=1`) == parallel, golden 값 대조
- [ ] `;trace on`으로 병렬 engage 실증 + engagement 카운터 delta
- [ ] 클라이언트-가시 행 반환 확인(집계 외 top-level SELECT)
- [ ] env-OFF(구경로) 무회귀
- [ ] CS 모드 debug 서버에서 라이브 실행(assert/crash/tracker leak 0)
- [ ] orphan-zero(정상/비정상 종료 + kill-9 후 임시파일 잔존 0)
- [ ] 필요 시 valgrind memcheck(invalid r/w/free 0) — 검증 쿼리 순간에만
- [ ] perf 비교 시: env -i 격리, warmup+median, CoV ≤ 15%, 동일 conf 확인
- [ ] 트리 원상복구 + 데몬 정리 + proof에 `cubrid_rel` 기록
