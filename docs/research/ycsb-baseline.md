# YCSB 성능 베이스라인 — 현행 브로커 경유(jdbc→cas→server) 구조 (#125)

측정일 2026-08-25. CAS 통합 맵(#112)의 마이그레이션 단계별 회귀 판정과 최종
"2-hop 제거 효과" 비교의 **유일한 기준선**.

## 측정 조건 (MEAS 기록)

| 항목 | 값 |
|---|---|
| 소스 | develop @ `5862371ba` (worktree `~/dev/worktrees/wf125-baseline`) |
| 빌드 | **release** (CMake preset `release`, RelWithDebInfo) → `~/release/CUBRID-wf125-baseline` (사용자 지시: 성능 측정은 release 고정) |
| 호스트 | 64코어, 188GB RAM, Linux 6.9.4 (단독 사용; wf109 서버 공존했으나 전 체크포인트에서 CPU 0.0–0.7%로 정지 상태 확인) |
| 스토리지 | **DB 볼륨+로그 SSD**(sdb, Samsung MZ7L33T8) `/home/cubrid/wf125-ycsb-db` — 최초 HDD(/data)에 만들던 것을 사용자 지적으로 중단·재로드 |
| 서버 conf | 하네스 QA 표준: `data_buffer_size=4G, log_buffer_size=2G, vacuum_worker_count=50, max_clients=200, data_buffer_neighbor_flush_pages=0` |
| 브로커 conf | BROKER1 port 33000, CAS 풀 고정 120 (`MIN=MAX=120`), `SQL_LOG=OFF`, query_editor OFF |
| 데이터 | usertable 10,000,000행 (YCSB 표준 스키마, VARCHAR(255) PK + 10×VARCHAR(100)) |
| 로드 | 생성 데이터 파일(YCSB `user<FNV64(i)>` 키를 Java `Utils.hash`와 비트 동일 재현, Python 교차검증) → SA `loaddb`(데이터 ~12분) → PK는 `loaddb --no-logging-index`(~1분). golden `ycsb_g` 보존, 측정은 `copydb` 복제본 `ycsb` |
| YCSB | 하네스 `~/dev/cubrid-perftools-internal/ycsb`, threads=100, recordcount=10M, **operationcount=20M**(사용자 축소), maxexecutiontime=1200, zipfian |
| 반복 | **워크로드당 1회 (C×1, A×1)** — median-of-3 철회(사용자 결정, 러닝타임). **차후 단계별 측정도 동일 프로토콜** |
| 스모크 게이트 | workloadc 100k ops 전건 `Return=0` (키 재현 정확성 엔드투엔드 확인) |

## (b) 처리량·레이턴시 베이스라인 (100 threads)

| 지표 | Workload C (read 100%) | Workload A (read50/update50) |
|---|---|---|
| **Throughput** | **130,686 ops/s** | **27,279 ops/s** |
| RunTime | 153.0s / 20M ops | 733.2s / 20M ops |
| READ avg | 756.5µs | 823.3µs |
| READ p95 / p99 | 1,314 / 1,707µs | 2,597 / 8,071µs |
| UPDATE avg | — | 6,474.1µs |
| UPDATE p95 / p99 | — | 18,095 / 29,231µs |
| 에러 | 0 (Return=0 × 20,000,000) | 0 (READ 10,000,595 + UPDATE 9,999,405) |

A의 처리량은 UPDATE 평균 6.5ms(READ의 ~8배)가 지배 — zipfian 핫 로우 쓰기
경합 + 커밋 로그 flush. 회귀 판정은 위 표의 Throughput·avg·p99를 기준으로 한다.

## (a) 단문 왕복 레이턴시 분해 (single-thread, PK SELECT, hot key, localhost, prepared)

`SELECT * FROM usertable WHERE ycsb_key='user6284781860667377211'`, 50k iter × 3 reps,
warmup 100, autocommit on. 도구: `/data/wf125-ycsb/scripts/{direct_cs_bench.c, cci_bench.c, JdbcBench.java}`.

| 경로 | mean (3 reps) | p99 |
|---|---|---|
| **직결 1-hop** (libcubridcs→server, `db_execute_and_keep_statement`) | **101.0 / 101.0 / 106.7µs** | 152–155µs |
| **CCI 2-hop** (→CAS→server, 동일 C 스택) | 135.4 / 134.4 / 133.3µs | 198–202µs |
| **JDBC 2-hop** | 103.3 / 121.2 / 132.2µs | 149–208µs |
| 직결 1-hop, **매회 재컴파일**(full, n=5k) | 511.8 / 481.2 / 466.7µs | 615–693µs |

### 판정

- **브로커 hop 순비용 ≈ +31µs/문장 (+30%)** — CCI 2-hop(≈134µs) − 직결 1-hop(≈103µs), 동일 C 스택 차분.
- **"2-hop이 레이턴시 2배" 주장은 불성립** (localhost 기준). 부하 시 평균 757µs는 hop이 아니라 큐잉·경합이 지배.
- **클라이언트측 SQL 컴파일 ≈ +380µs/문장** (487µs vs 103µs, 4.7×) — statement 재사용(CAS 풀링)이 현행 구조 성능의 결정 요인. B안에서 컴파일러를 서버로 편입해도 **서버측 statement/plan 캐시가 등가 이상으로 필수**라는 정량 근거 (#124 SER 실측·#116 statement 풀링 재배치의 입력).
- 실네트워크(비-localhost)에서는 hop당 RTT가 가산되므로 +31µs는 하한. 절대치보다 **동일 조건 재측정 차분**으로 쓸 것.
- 한계: 단일 키(핫 캐시), 단일 스레드, loopback. 분해 목적에는 충분하나 일반화 금지.

### dbi API 발견 (B안 구현에 유관)

`db_execute_statement`는 컴파일된 문장의 **재실행을 거부**한다("Function called
with missing or invalid arguments"). 재실행은 CAS가 쓰는
`db_execute_and_keep_statement`(cas_execute.c:1126) 경로만 가능 — 서버 편입 시
statement 수명 관리가 이 API 계약을 승계해야 함.

## 원자료

호스트 `/data/wf125-ycsb/`: `results/{smoke_workloadc,workloadc_run1,workloada_run1,decomp_*}.log`,
`logs/`(로드·체인·서버 제어), `scripts/`(생성기·벤치 소스·RUNBOOK.md·env.sh).
golden DB `ycsb_g`는 `/home/cubrid/wf125-ycsb-db`에 보존(재측정 시 `copydb`로 복제).
