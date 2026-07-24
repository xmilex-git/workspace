# Issue #163 Phase 3 — 리뷰 수정·검증 및 단일 JVM ceiling 분석 (2026-07-24)

## 산출물/메타데이터

- Engine: `xmilex-git/cubrid` `codex/jdbc-direct-phase3` — 리뷰 수정 `7f12419d0`,
  submodule bump `94864edb4` (base = Phase 2 `c67d62c78`)
- JDBC: `xmilex-git/cubrid-jdbc` `codex/jdbc-direct-phase3` — 리뷰 수정 `83781d2`,
  hot-path 최적화 `4b539be` (base = `5b795b7`)
- 빌드: clean rebuild(`just rebuild jdbc-direct-poc-release jdbc-direct-phase3`),
  `cubrid_rel` = **11.5.0.2316-7f12419** RelWithDebInfo, `ENABLE_JDBC_DIRECT_POC=ON`.
  engine 바이너리는 `7f12419d0` 기준(이후 커밋은 JDBC submodule pointer만 변경).
- conf md5: cubrid.conf `b032dbf5…788a` (data_buffer_size=8G), broker
  `96ffb841…bdac` (BROKER1 SQL_LOG=OFF, STATEMENT_POOLING 기본 ON)
- JVM: OpenJDK 1.8.0_412, 옵션 기본값(YCSB ycsb.sh 기본). 실행 명령·원자료:
  `.git_ignored_dir/scratch/ycsb/`(load3, results3-*, final3/), 프로파일:
  `.git_ignored_dir/scratch/prof3/`(fast-cpu/alloc/lock, opt1-lock, collapsed 형식)

## 1. Phase 2 리뷰 항목 수정 (전건 테스트 동반)

| # | 항목 | 수정 | 검증 |
|---|---|---|---|
| R1 | isolation 적격성 | "default" = 유효 isolation == `TRAN_READ_COMMITTED`(direct attach가 등록하는 값). prepare 시 `GET_DB_PARAMETER`로 1회 해석·캐시, execute마다 캐시 비교. 불일치 → CAS 강등 | serializable-fallback-parity PASS + QPS delta 201/200 (전량 CAS 실증) |
| R2 | CAS handle lifecycle | 근본 원인: pooling OFF에선 CAS auto-commit마다 non-holdable handle 전부 해제(`ux_end_tran_cleanup`) → 유지 handle 즉사. **direct 적격 조건에 statement pooling ON 추가**(JDBC 게이트 + take_xasl 서버 belt). pooling ON에선 close()가 CLOSE_USTATEMENT를 정확히 1회 전송 | prepare/close 20k·40k churn: cub_cas RSS delta **0KB**, 오류 0; direct/CAS 교대 실행 후 close PASS; pooling OFF 전환 시 전량 CAS(QPS +201)로 정확성 보존 |
| R3 | setMaxRows 등 실행 옵션 | maxRows/maxFieldSize/scrollable/sensitive/queryPlan/onlyPlan/executeAll/async/queryTimeout>0 → CAS 강등 (holdable은 전체 결과를 클라이언트에 실체화하므로 의미 보존, 강등 불요) | maxrows-parity PASS + QPS delta 202/200 |
| R4 | TAKE_XASL 오류 분류 | `CAS_ER_ARGS` 명시 거절만 fallback, 그 외 UJciException/IOException 전파(desync 연결로 계속 실행 금지) | pooling-OFF 경로가 CAS_ER_ARGS 분기 실증; 코드 리뷰 |
| R5 | protocol 경계 | request: len<0/1MiB 초과/DB_ALIGN overflow/pointer overflow-safe 비교/trailing bytes fail-fast. response: 값 삽입 **전** 상한 검사(일시 초과 할당 제거). JDBC: rowCount×colCount×8 ≤ payload 검증 후 배열 할당 | malformed 9종(bad-version/truncated/bad-tag/negative-len/huge-len/truncated-payload/trailing/param-overrun/bogus-xasl) 전부 에러 응답 + 서버 생존 |
| R6 | ADR 문서 일치 | TLV 실구현 `{tag, length, payload}` 기준으로 ADR 0002 정정(+R1~R5 결정 반영) | ADR 0002 갱신 |

필수 검증 매트릭스: Smoke 7/7 + Smoke3 6/6 + malformed 9/9 PASS, direct QPS delta 2/500
(execute가 CAS 미경유), CAS 회귀 없음, `git diff --check` 양 repo clean, tranlist에
direct client 잔존 0, `ER_SES_SESSION_EXPIRED` 0, error-log flood 없음(53B).

## 2. 가설별 판정 — "단일 JVM ceiling"

지시된 8개 가설을 증거로 판정한다. 결론 먼저: **"단일 JVM 내부가 병목"은 성립하지
않는다.** 현상의 실체는 서버 수명 내에서 명멸하는 **양봉(bimodal) regime**이며, 느린
쪽은 서버측 대기(worker 파킹/wakeup)와 정합한다.

| 가설 | 판정 | 증거 |
|---|---|---|
| 1. per-execute allocation | 기각(주원인 아님) | asprof alloc: 총 12.5GB/12s 중 UDirectPocConnection.execute(char[]/byte[]) 등 정상적 per-op 할당. 같은 할당 프로파일로 fast state 145–155k 도달. GC young 7/s, GC 시간 <1% |
| 2. VARCHAR 복사/charset decode | 기각 | alloc 29.5%가 String decode용 char[]이지만 CPU에선 execute 6.3%뿐. fast state에서 병목 아님 |
| 3. Object[][] 중간 표현 | 기각 | alloc 기여 소량(UResultTuple 1.1%) |
| 4. Buffered/Data stream framing | 부분(고정 비용) | CPU 상위: ByteArrayBuffer.writeToStream 22.9% + sendRequest 19.7% + readRecord 18.4% — per-op 고정 비용이지만 fast/slow 공통이라 regime 원인 아님. 향후 최적화 후보 |
| 5. socket/serialization | 부분(위와 동일) | UTimedDataInputStream.read 12.9% |
| 6. JVM/GC 설정 | 기각 | jstat: GC pause 누적 0.25s/분 미만, full GC 0 |
| 7. process-global contention | **발견·수정** | asprof lock: 유일한 전역 직렬화 지점 = 매 auto-commit의 `UUnreachableHostList.getInstance()`(synchronized static, class monitor). 필요 분기 안으로 이동(`4b539be`) → lock 이벤트 0. 단 fast state 수치엔 중립(145.5k→148.2k) — 느린 regime의 단독 원인으로는 미확정 |
| 8. server queue/lock × client timing | **유력(방향 확정)** | 아래 regime 분석 |

### 느린 regime 분석

- **재현**: 동일 서버 수명에서 연속 벤치 런 시 간헐 발생. 최종 3-rep 세트에서 생포:
  t32-direct = 76.9k/141.8k/73.4k (CAS 동시간 96.0–96.3k 안정, CoV 0.1%).
  연속 15s 런 9회에서 155k→138k→134k→120k **단조 열화** 구간과 76.6k 급락, 이후
  자발 회복 관찰. 서버 재시작은 항상 fast로 리셋.
- **wchan 추세**(열화 구간): cub_server parked threads(futex_wait) 67→79 증가,
  running 20→12 감소 — **worker pool이 점점 깊이 파킹**되는 신호.
- **기각된 트리거**(각 대조 실험): 5M load 동일 수명(직후 146.5k), 세션 누적(150-conn
  churn 후 154k), vacuum 백로그(UPDATE 890k 직후 128k→153k), 선행 단일 런 A–F 조합
  (전부 fast), 스레드 수 축소(115 불변), CPU 클럭(2.7GHz 유지), client 락/GC/할당(가설 1–7).
- **정합 요소**: 느린 상태에서 서버 CPU 583%(fast 1302%), 클라이언트는 socketRead
  대기 87%; 동시 2T probe JVM이 같은 JVM을 130k로 끌어올림(추가 트래픽이 pool을 깨워
  둠); CAS는 무거운 per-op(CPU ~190µs)로 pool을 계속 바쁘게 해 무감각.
- **결론**: direct의 저CPU(≈76µs/op)·고빈도 요청 패턴이 서버 worker pool의
  파킹/wakeup 정책과 상호작용하며 요청마다 wakeup 비용을 무는 상태로 전이한다.
  확정 코드 지점(worker pool 정책 vs css dispatch)은 미고정 — **후속 fact-finding**:
  느린 regime 발생 시 cub_server off-CPU 프로파일(perf sched/BPF) + thread_worker_pool
  파킹 카운터 계측. 후보 완화책: direct 연결 전용 스레드 모드, pool 파킹 타임아웃 조정.

## 3. 최종 벤치마크 (phase3+opt1 바이너리, 3-rep, 20s, 재시작·warm 후)

| 지점 | rep1/2/3 (ops/s) | median | 변동 |
|---|---|---|---|
| t2 CAS | 11,778 / 12,730 / 13,118 | **12,730** | CoV 5.4% |
| t2 Direct | 18,662 / 18,481 / 19,040 | **18,662** | CoV 1.5% |
| t32 CAS | 96,261 / 96,027 / 96,297 | **96,261** | CoV 0.1% |
| t32 Direct | 76,873 / 141,761 / 73,366 | (양봉 — median 무의미) | slow-mode 73–77k / fast-mode 120–165k |

- t2: Direct **+47%** (median 기준, 안정)
- t32: fast regime에서 Direct 120–165k vs CAS 96k (**+25~+72%**), slow regime에서
  73–77k (**-20~-24%**). regime 트리거 미고정 상태이므로 32T 판정은 "fast regime
  기준 우위 + regime 리스크 상존"으로 보고한다. 단순 median/평균 제시는 왜곡이라
  전 rep을 공개한다. percentile은 rep별 원자료(final3/)에 보존(HDR merge 미수행).

## 4. 잔여 작업·위험

1. 느린 regime의 코드 지점 확정(off-CPU 프로파일) — 32T 성능 주장의 신뢰도를 좌우
2. framing/copy 최적화(CPU 61%가 socket/framing 고정 비용) — vertical 후보 #2
3. `cancel()` 무효, SQLState parity 미구현(known limitation 유지)
4. 공유 호스트 특성상 외부 부하 교란 완전 배제 불가 — 전용 환경 재검 권장
5. 제품화 결정(연결 모델·session ownership·인증 등)은 design 선택지 문서로 grill 대기
