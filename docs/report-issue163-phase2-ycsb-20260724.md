# Issue #163 Phase 2 — Generic direct prepared execution + YCSB Workload C 결과 (2026-07-24)

## 산출물

- Engine: `xmilex-git/cubrid` branch `codex/jdbc-direct-phase2-ycsb` (`c67d62c78`, base = Phase 1 `47431218c`)
- JDBC: `xmilex-git/cubrid-jdbc` branch `codex/jdbc-direct-phase2-ycsb` (`5b795b7`, base = Phase 1 `7ae770c`)
- 설계 근거: `docs/adr/0002-jdbc-direct-phase2-wire-protocol.md`
- 빌드: `cubrid_rel` = CUBRID 11.5.0 (11.5.0.2314-4743121) 64bit release, RelWithDebInfo,
  `ENABLE_JDBC_DIRECT_POC=ON`, preset `jdbc-direct-poc-release`

## 구현 요약 (ADR 0002 이행)

- protocol v2: `NET_SERVER_JDBC_DIRECT_POC_EXECUTE` 단일 generic opcode. request/reply 양쪽
  version int, mismatch fail-fast. reply = `{version, status(errid), tran_state, row_count,
  col_count, [tag,len,payload]*}` single-response, 1 MiB 명시적 상한.
- bind: TLV(VARCHAR/INT/NULL) → 서버 handler가 DB_VALUE 조립 후 `or_pack_db_value` 스트림으로
  재포장해 `xqmgr_execute_query()`에 전달.
- 적격성: property opt-in AND SELECT AND autoCommit AND 지원 컬럼 type. 위반 시 기존 CAS 코드가
  default branch로 실행(강등). `take_xasl`은 host var 허용 + srv handle 유지로 변경(강등 지원).
- 결과 디코딩은 CAS fetch와 동일하게 per-column charset 사용(스모크에서 한글 parity로 검증).

## 검증

### Smoke (7/7 PASS)

`SELECT 1` parity, VARCHAR bind point-SELECT 15회 재사용 parity(한글 포함), multi-row+NULL
parity, INT bind parity, 미지원 컬럼(DATE) 강등, 미지원 bind(BigDecimal) 강등,
autoCommit=false 강등 — 전부 CAS 결과와 문자열 일치.

### 신경로 실증 (SSOT 실수 2 대응)

동일 point-SELECT 500회: CAS URL → broker QPS +501, Direct URL → **+2**(prepare+take_xasl뿐).
checksum 동일. execute loop가 CAS를 완전히 우회함을 카운터로 실증.

## YCSB Workload C 결과

환경: 5,000,000 rows(≈5 GiB, fieldcount 10×100B), `data_buffer_size=8G`(측정 전 warm),
zipfian, 지점당 warmup 후 20초 1회, CPU/NUMA pinning 없음, broker `SQL_LOG=OFF`,
같은 빌드·conf·DB에서 URL만 교체. 호스트: 64 logical CPU Xeon Silver 4216.

| 지점 | CAS | Direct | Direct/CAS |
|---|---|---|---|
| 2 threads | 13,008 ops/s · avg 151µs · p99 215µs | 19,123 ops/s · avg 102µs · p99 148µs | **+47% / avg -32%** |
| 32 threads (1 JVM) | 97,630 ops/s · avg 323µs · p99 576µs | 72,598 ops/s · avg 435µs · p99 557µs | **-26%** |
| 32 threads (2 JVM×16) | 96,280 ops/s · avg 328µs · p99 711µs | 140,598 ops/s · avg 223µs · p99 451µs | **+46% / p99 -37%** |

드리프트 센티널: t2-CAS 재측정 13,451 ops/s (+3.4%) — 세션 안정.

### 32-thread 단일 JVM 역전의 원인 판별

pidstat(순간 CPU, 10s 평균):

| 32 threads run | cub_server | cub_cas 합 | java |
|---|---:|---:|---:|
| CAS | 1007% | 859% | 293% |
| Direct | 583% | 92% | 220% |

- Direct run에서 CAS 프로세스는 idle(92%) → 강등 누수 없음.
- Direct는 서버측 CPU/op ≈ 76µs로 CAS 경로 서버측(server+CAS ≈ 190µs/op)의 절반 이하인데
  단일 JVM throughput이 ~75k에서 포화(8/16/32 threads: 65k/75k/77k).
- 같은 32 direct 연결을 2 JVM×16으로 쪼개면 140.6k ops/s → **병목은 서버가 아니라 JDBC
  클라이언트 JVM 내부**. 서버측 direct 경로는 CAS 최고치(98k) 대비 +43% 이상을 소화한다.
- 클라이언트 JVM ceiling의 근본 원인(할당/GC, framing 등)은 Phase 3 과제(JFR 프로파일).

## Acceptance (ADR 0002) 판정

- [x] YCSB C direct run 에러 0 — `Return=ERROR` 0, `ER_SES_SESSION_EXPIRED` 0, server err log 52KB(플러드 없음)
- [x] CAS vs Direct 비교 보고서(본 문서, throughput+p50/95/99+원자료 `.git_ignored_dir/scratch/ycsb/results/`)
- [x] run 세트 후 tran/session 누수 0 — tranlist에 direct client 잔존 0 (ACTIVE 항목은 broker pool의 idle CAS)

## 남긴 것 / Phase 3 이월

- 단일 JVM direct client ~77k ops/s ceiling 근본원인 (JFR)
- SQLState parity, cancel, cursor, direct UPDATE(Workload B), CAS detach, auth/TLS (ADR 0002 참조)

## 재현 자료

- YCSB: `.git_ignored_dir/scratch/ycsb/` (bench.sh, load.log, results/*.log)
- Smoke: `.git_ignored_dir/scratch/jdbc-direct-smoke/`
- DB: `.git_ignored_dir/scratch/ycsb/db` (16G, 재측정용으로 보존)

## 정정 (같은 날 추가 실험 — 이전 귀속 supersede)

"32T 단일 JVM 역전 = JDBC 클라이언트 JVM 내부 병목" 귀속은 **반증되었다**. 추가 증거:

- jstack 10회 집계: 워커 샘플 87%가 `socketRead0`(서버 응답 대기), BLOCKED 모니터 0, GC 시간 <1% → JVM 내부 락/GC 무죄.
- 혼합 프로브: 느린 32T JVM 옆에 2T probe JVM을 띄우자 같은 JVM이 130k ops/s로 상승.
- **서버 재시작 후에는 단독 1×32 direct가 140.9–144.5k ops/s** (CAS 동시점 100.9k, **+40%**).
  재시작 전 단독 1×32는 72–77k에서 재현적으로 포화했다.

정정된 사실: CAS 32T는 서버 수명과 무관하게 ~97–101k로 안정. direct 32T만 첫 서버
수명(5M row load 직후)에서 느린 regime(72–77k)에 갇혔고, 서버 재시작으로 해소됐다.
첫 수명 내에서 2×16 JVM 분할이 140k를 낸 것도 이 regime과 교란되어 있어 클라이언트
토폴로지 효과는 확립되지 않는다.

**Phase 3 fact-finding 항목으로 이월**: 느린 regime의 트리거 식별. 유력 용의:
대량 INSERT 직후의 vacuum 잔무 경합, direct 세션 누적 상태, worker pool parking.
재현 레시피: 5M row 재적재 → 같은 서버 수명에서 즉시 32T direct 측정(느린 regime 기대)
→ 재시작 후 재측정(140k 기대) → 느린 regime 중 cub_server off-CPU 프로파일.

최종 수치(안정 regime, post-restart): **32T direct 140.9k vs CAS 100.9k (+40%)**,
2T direct +47% — 저동시성·고동시성 모두 direct 우위.

## 보고 오류 정정 (Phase 3 리뷰 지적, 2026-07-24)

1. **p50**: YCSB 표준 출력에는 p50이 없고 원자료에도 없다. "p50/p95/p99 확보"는 오기이며
   실제 확보 항목은 Average/p95/p99다. 본문 해당 표기는 이 정정으로 대체한다.
2. **2 JVM 실행 시간**: 2×16 분할 런은 `maxexecutiontime=18`(약 18초)로 실행되었다.
   "20초"로 적은 부분은 오기.
3. **p99 평균 금지**: 32T(2×16) 행의 p99 451µs는 두 JVM 값(446/457µs)을 단순 평균한
   것이어서 무효다. 개별 JVM 값을 각각 표기하는 것이 옳다: split-a p99=446µs,
   split-b p99=457µs (CAS 2×16: 715/708µs). HDR histogram merge는 수행하지 않았다.
4. 이 정정은 위 "정정 (같은 날 추가 실험)" 섹션과 함께 Phase 3 보고서
   (`report-issue163-phase3-review-analysis-20260724.md`)로 이어진다.
