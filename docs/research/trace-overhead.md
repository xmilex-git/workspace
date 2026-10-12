# SET TRACE ON 실행 비용 — 원인과 설계

이어지는 작업: `docs/research/trace-accuracy-115.md`(CBRD-27599) 뒤. 엔진 기준: `CBRD-27599-parallel-trace-stats` 1c69b5120 (develop be683e04c + CBRD-27599 수정). release 빌드 `~/release/CUBRID-trace-accuracy`, 데이터 TPC-H SF10 `~/databases/trace115/cur`.

질문: `SET TRACE ON`(과 `@collect_exec_stats`)을 켜면 왜 느려지고, PostgreSQL `EXPLAIN ANALYZE`는 왜 덜 느려지나. release 기준으로 trace를 켜도 느려지지 않게 한다.

## 측정 (2026-10-11, release, 병렬 기본 conf)

실행 모드: P = 질의만, T = `SET TRACE ON; 질의; SHOW TRACE`, S = `SET @collect_exec_stats = 1; 질의; SHOW EXEC STATISTICS ALL`.
증거: `.git_ignored_dir/scratch/trace-perf/` (m1 = 43개 질의 × 5라운드 중앙값, m2 = perf 프로파일 q18+q01+q06, m3 = 다른 세션에 미치는 영향).

### 전체 행렬 (m1, 43개 질의, 5라운드 중앙값)

- T/P 중앙값 **1.126**, 최댓값 **1.93**(s04_index_covering); S/P 중앙값 1.173. 합계 T 371 s / P 334 s = 1.11.
- 최악 5: s04_index_covering 1.93, s21_not_exists 1.81, q13 1.63, s05_nl_memoize 1.55, s20_in_subquery 1.48 — 인덱스 scan·NL join·hash group by. 0.02 s짜리 질의의 S/P 1.8~1.9는 `SHOW EXEC STATISTICS` 출력(csql 고정 비용)이다.
- 라운드 사이 소음이 크다(27개 질의에서 P max/min > 1.15; q07 7.4배). 다른 lane 7개와 perf 측정이 같은 호스트에서 돌았기 때문. 비교는 같은 lane 안의 모드 교대(P T S 순환)로만 한다.

### 다른 세션에 미치는 영향 (m3)

victim q06(P)의 중앙값: 혼자 4.97 s, 옆에서 q01 P 4.77 s, 옆에서 q01 T 4.93 s → (c)/(b) = 1.03. 전역 게이트의 비용은 있지만 작다(소음 수준).

### 최악 사례 프로파일 (m4: s04, s21, q13 각 3회 묶음, T/P 1.99 / 1.72 / 2.03)

| 사례 | T에서 커진 심볼 | 원인 |
|---|---|---|
| s04_index_covering | `perfmon_mvcc_snapshot` 0 → **47.9 %** (추가 사이클의 94 %), `perfmon_get_from_statistic` 7.7 % | 레코드 가시성 검사(`mvcc_satisfies_snapshot`)마다 `perfmon_add_stat_at_offset` → 전역 `lock addq`. 샘플의 97.9 %가 그 명령 다음에. `extended_statistics_activation` 기본값에 `MVCC_SNAPSHOT`이 들어 있다(기본 동작). |
| s21_not_exists | `btree_range_scan` 1.0 → 14.0 %, `perfmon_pbx_unfix` 7.9 %, vdso(`rdtscp`) 3.3 %, `perfmon_pbx_fix_acquire_time` 2.9 %, `perfmon_pbx_fix` 2.1 % | `btree_range_scan` 안의 핫 명령은 전부 `lock addq $1,(%rdx)` + `lock add %rcx,0x8(%rdx)` = `perfmon_time_at_offset`의 count·total 원자 연산(btree 타이머 `BT_RANGE_SEARCH`, `BT_LEAF`). |
| q13 | 같은 구성: perfmon_* 17.5 %, tsc 1.1 %, vdso 4.5 % | |

세 사례에서 추가 사이클의 대부분은 **전역 통계 배열에 대한 lock 접두 원자 연산**이고, 시계(`rdtscp`+`clock_gettime`)는 3~5 %p다.

### perf 프로파일 (m2, `cycles:u`, T1 97.4 s / P1 86.0 s = 1.13)

T에서만 커지는 심볼 (전체 사이클 대비):

| 심볼 | P1 | T1 | S1 | 원인 |
|---|---|---|---|---|
| `pgbuf_set_dirty` | 0.64 % | 5.21 % | 4.04 % | 안에 인라인된 `perfmon_inc_stat(PSTAT_PB_NUM_DIRTIES)`의 `lock addq` (전역 `global_stats` 캐시 라인). 샘플의 87.9 %가 그 원자 연산 바로 다음 명령에 찍힌다. P에서는 같은 원자 연산이 싸다: 그 라인을 건드리는 스레드가 하나뿐이다. T/S에서는 px worker 넷이 fix마다 같은 라인(`NUM_FETCHES` 등)에 원자 연산을 하므로 라인이 코어 사이를 오간다. |
| `perfmon_get_from_statistic` | 0 | 1.92 % | 0 | `scan_next_scan_local`이 행마다 4번, `qexec_execute_mainblock`이 호출마다 7번 부르는 외부 함수. |
| `tsc_getticks` + `clock_gettime` + `tsc_elapsed_*` | 0.01 % | 0.95 % | 0.35 % | 행마다 2번, fix마다 2~3번 시계를 읽는다. 이 호스트에서 rdtsc 대신 `clock_gettime`을 쓴다(아래 결함 3). |
| `perfmon_pbx_fix/unfix/fix_acquire_time` | 0 | 0.53 % | 0.50 % | fix·unfix마다 다차원 카운터 갱신(전역 원자 연산 포함). |
| `pgbuf_fix_release` | 0.49 % | 1.08 % | 1.07 % | 위 추적 코드 중 인라인된 부분. |

합계 약 8.7 % ≈ T1/P1 − 1. 즉 **비용의 대부분은 시계 읽기가 아니라 전역 통계 배열에 대한 원자 연산(캐시 라인 경합)** 이고, 그 다음이 행 단위 trace 집계의 함수 호출이다.

## PostgreSQL과의 구조 차이

| | CUBRID | PostgreSQL |
|---|---|---|
| 카운터 저장 | `pstat_Global.global_stats[]` 하나에 모든 스레드가 `ATOMIC_INC_64` | backend마다 자기 `pgBufferUsage` 구조체에 일반 덧셈. 공유 통계는 트랜잭션 끝에 모아서 보낸다. |
| 켜는 범위 | `n_watchers > 0` 이면 **서버 전체**가 추적 모드(페이지 fix·unfix 시간, latch, btree, mvcc 등 150여 곳). 한 세션이 trace를 켜면 다른 세션도 느려진다. | 카운터는 항상 켜져 있고 싸다. 시간 측정은 `EXPLAIN ANALYZE`를 실행한 backend의 plan node에서만. |
| 버퍼 시간 | fix마다 시작·끝 시계를 읽어 `fix_acquire_time`에 더한다(hit도 포함). | `track_io_timing`을 켠 경우에만, 실제 디스크 읽기에만 시계를 읽는다. hit 경로에는 시계가 없다. |
| 행 단위 시간 | `scan_next_scan_local`마다 시계 2번 + usec 변환(나눗셈) + 통계 읽기 4번 | node마다 tuple당 시계 2번(`InstrStartNode/StopNode`). 같은 구조. |

## 결함·비용 목록

| # | 위치 | 내용 |
|---|---|---|
| 1 | `perfmon_add_at_offset`, `perfmon_time_at_offset`, `perfmon_set_at_offset`, `perfmon_add_stat_at_offset` (`perf_monitor.h`) | 전역 배열 원자 연산. 병렬 worker 수만큼 라인 경합. 추적을 켜지 않아도 `NUM_DIRTIES`, `NUM_IOREADS` 등 무조건 세는 통계는 이 비용을 낸다. |
| 2 | `perfmon_is_perf_tracking()` (`perf_monitor.h`) | `n_watchers > 0` 전역 게이트. 세션 하나가 서버 전체의 추적을 켠다. |
| 3 | `check_power_savings` (`tsc_timer.c`) | `/sys/devices/system/cpu/sched_mc_power_savings`를 읽는데 이 파일은 2012년 커널 3.5에서 사라졌다. 파일이 없으면 `power_Savings = 1`이 되어 `constant_tsc` CPU에서도 모든 tick이 `clock_gettime`이다(이 호스트 포함). `tsc_elapsed_time_usec`는 호출마다 64비트 나눗셈. |
| 4 | `pgbuf_fix_release` 2240-2571, `pgbuf_unfix` 3059-3085 (`page_buffer.c`) | 추적 중 fix마다 시계 2~3번, 페이지 타입 조회, `perfmon_pbx_fix`, `perfmon_pbx_fix_acquire_time`(원자 3번, max는 CAS 루프), unfix마다 `perfmon_pbx_unfix`. hit 경로도 전부. |
| 5 | `scan_next_scan_local` 5935-6050, `qexec_execute_mainblock` 15911-15945, hash list scan 4381, `scan_manager.c` 6941 | 행마다 `perfmon_get_from_statistic` 4번(외부 함수, 트랜잭션 인덱스 조회와 분기 포함), 시계 2번, 나눗셈. |

## 설계 (단일 lane)

병렬 lane은 서로 양립할 수 없는 구현에만 쓴다(사용자, 2026-10-11). 아래 항목은 모두 양립하므로 한 lane에서 순서대로 커밋한다(C1 = 항목 1, C2 = 항목 2+5, C3 = 항목 4). 항목 4(시계를 대기 경로에서만 읽기)만 의미가 바뀌므로 C2 빌드와 C3 빌드를 따로 재서 4의 몫을 확인한다. 항목 3(세션 단위 게이트)은 m3에서 효과가 3 %뿐이고 항목 2가 공유 쓰기를 없애면 더 줄어들므로 **보류**: C3 빌드로 m3 시나리오를 다시 재서 (c)/(b) > 1.03이면 그때 넣는다.

규칙(`cpp-perf-rules`): PAR-01·COH-12 (공유 원자 연산 → 소유 분할), MEM-03/GLOB-02 (false sharing), CC-05 (행 루프의 외부 함수 호출 제거), BR-04 (불변 분기 제거), MEAS-04/07 (중앙값, 분산 함께 보고).

### 1. tick 소스 (`tsc_timer.c`)

- `check_power_savings`: `/proc/cpuinfo`의 flags에 `constant_tsc`와 `nonstop_tsc`가 모두 있으면 `power_Savings = 0`(rdtsc), 아니면 1(`clock_gettime`). 옛 sysfs 파일 검사는 지운다.
- `tsc_elapsed_time_usec`의 rdtsc 경로: `tsc_init`에서 `cpu_Clock_rate`로 역수(곱셈·시프트)를 한 번 만들어 두고 호출마다 나눗셈 대신 곱셈. 결과는 같은 usec 정수(반올림 차이 ≤ 1 usec 허용).
- 출력 형식·구조체(`TSC_TICKS`, `TSCTIMEVAL`)는 그대로. 호출처 변경 없음.

### 2. 스레드 소유 통계 배열 (`perf_monitor.h/.c`, `thread_entry.hpp`)

- `cubthread::entry`에 `UINT64 *m_perf_stats` (크기 `PERFMON_VALUES_MEMSIZE`, 첫 갱신 때 `calloc`). thread manager의 entry는 프로세스가 사는 동안 재사용되고 소멸하지 않으므로 은퇴 합산이 필요 없다(`entry` 소멸자에서 해제만). SA_MODE도 entry가 하나이므로 같은 코드.
- `perfmon_set_at_offset`(게이지, `PEEK`류)은 지금처럼 전역 배열에 쓴다(드물다).
- 핫 경로 `perfmon_add_at_offset` / `perfmon_time_at_offset` / `perfmon_add_stat_at_offset` / `perfmon_set_at_offset`: 전역 `ATOMIC_*` 대신 `thread_p->m_perf_stats[offset] += amount` (COUNTER_TIMER는 count·total 덧셈, max 비교). `tran_stats`(`is_watching`일 때 일반 덧셈)와 px worker의 `m_px_stats` 경로는 그대로 둔다.
- 전역 읽기 `xperfmon_server_copy_global_stats` 등 `pstat_Global.global_stats`를 읽는 곳(모두 `perf_monitor.c` 안): 은퇴 배열 + 살아 있는 모든 entry의 `m_perf_stats` 합(`cubthread::get_manager ()->map_entries`). COUNTER_TIMER의 max는 스레드 사이 최댓값. 읽는 쪽은 다른 스레드가 쓰는 중인 값을 그냥 읽는다(8바이트 정렬 정수, 단조 증가; 찢어진 읽기는 x86-64에서 없고 형식상 relaxed atomic load로 읽는다).
- 읽기 비용은 statdump 한 번에 (entry 수 × 값 수) 덧셈. entry 수와 `PERFMON_VALUES_MEMSIZE`를 구현 때 찍어서 설계 문서에 적는다.
- `perfmon_get_from_statistic`(trace의 행 단위 델타 읽기): 지금 의미(이 트랜잭션/px worker의 누적값) 그대로, 헤더의 `STATIC_INLINE`으로 옮긴다. 지금은 libcubrid 안에서도 PLT를 거치는 외부 호출이다(`perfmon_get_from_statistic@plt`가 프로파일에 보인다).

### 3. (보류) 추적 게이트를 세션 단위로 (`perf_monitor.h`, `thread_entry.hpp`)

- `perfmon_is_perf_tracking (thread_p)`: worker 스레드(`TT_WORKER`)는 `thread_p->m_perf_tracking`(요청 시작에 트랜잭션에 바인딩될 때 `is_watching[tran_index]`에서 복사, px worker arming 때 부모에서 복사, `perfmon_start_watch/stop_watch`가 자기 스레드 값도 갱신). 그 밖의 스레드(vacuum, flush, log 등 daemon)는 지금처럼 `n_watchers > 0` — DBA가 세션에서 `@collect_exec_stats`를 켜고 statdump로 daemon 타이머를 보는 쓰임을 지킨다.
- 호출처(`page_buffer.c` 56, `btree.c` 60, `mvcc.c` 25, 기타)는 인자만 추가. `thread_p`가 없는 곳은 `thread_get_thread_entry_info ()`.
- 효과: 다른 세션이 trace를 켜도 내 세션은 추적 코드를 타지 않는다(m3로 확인).

### 4. 시계는 기다린 경로에서만 (`page_buffer.c`)

- `pgbuf_fix_release`: 시작 tick을 함수 입구에서 읽지 않는다. latch 대기에 들어가기 직전, 디스크 읽기 직전, lock 대기 직전에만 tick을 읽고 끝 tick과의 차를 `fix_wait_time`/`holder_wait_time`/`lock_wait_time`에 넣는다. hit이고 대기 없는 fix는 시간 0, 카운터(`NUM_FETCHES`, `perfmon_pbx_fix`)는 그대로 센다.
- `fetch_time`(`PSTAT_PB_PAGE_FIX_ACQUIRE_TIME_10USEC`)의 의미: "페이지를 얻으려고 기다린 시간"(I/O, latch, lock). PostgreSQL `track_io_timing`과 같은 뜻. 사용자 승인(2026-10-11 Q3).
- `pgbuf_unfix`: 시계 없음(지금도 없음). 페이지 타입 조회와 `perfmon_pbx_unfix`는 유지(일반 덧셈이 되어 싸다).

### 5. 행 단위 trace 집계 (`scan_manager.c`, `query_executor.c`)

- 항목 2의 인라인 읽기로 `perfmon_get_from_statistic` 호출 비용을 없앤다. 시계는 행마다 2번 그대로(PostgreSQL과 같은 구조), 항목 1로 rdtsc + 곱셈.
- 구조체·출력 변경 없음.

### 바뀌지 않는 것

- `SHOW TRACE` 출력 형식과 `fetch`/`ioread`/`rows`/`readrows` 값(CBRD-27599 TC 13개, TPC-H trace 비교로 확인).
- `SHOW EXEC STATISTICS`, `statdump` 항목과 뜻. 단, 실행 중인 요청의 카운트가 statdump에 보이는 시점은 지금과 같다(지금도 즉시 반영; 설계 2는 읽을 때 합치므로 지연 없음).
- `extended_statistics_activation` 플래그 의미.

## 채택 기준 (사용자 승인 Q4)

release, TPC-H SF10, 병렬 기본 conf, DML 제외 43개 질의, 5회 중앙값. 질의별 T/P의 중앙값·최댓값. P가 나빠지면 안 된다(P_after/P_before 중앙값 ≤ 1.00 ± 소음). S의 T/P도 보고.

## 구현 결과 (2026-10-12, worktree `~/dev/cubrid-worktree/trace-overhead`, 1c69b5120 위)

| 커밋 | 내용 | 설계와 다른 점 |
|---|---|---|
| C1 `e5e7ef30d` | rdtsc 선택(`constant_tsc`+`nonstop_tsc`), 나눗셈 → `(10^6 << 64)/rate` 곱셈 | `get_clock_freq`가 읽던 `/proc/cpuinfo` "cpu MHz"는 TSC 주기가 아니라 현재 코어 클럭(이 호스트 1.2~2.9 GHz, TSC 2.1 GHz)이라 rdtsc로 바꾸면 시간이 최대 40 % 틀린다. CLOCK_MONOTONIC 대비 2 ms 측정(프로세스당 1회)으로 바꿨다. 경과 시간은 "변환한 두 시각의 차"(구간마다 내림하면 행당 0.5 usec씩 사라져 직렬 s21의 heap 시간이 537 → 198 ms로 줄었다). |
| C2 `9f09ba92c` | `cubthread::entry::m_perf_stats`(10790값 = 86 KB, 첫 갱신 때 `calloc`), 핫 경로 일반 덧셈, `xperfmon_server_copy_global_stats`가 살아 있는 entry 합산(`get_all_entries`, 4313 + main), `perfmon_get_from_statistic` 헤더 인라인 | entry가 소멸하지 않으므로 은퇴 합산 없음. `thread_p == NULL`·할당 실패는 예전 원자 경로. 메모리: 추적 중 통계를 갱신한 스레드마다 86 KB(q13 한 번에 16개; 최악 4314개 = 372 MB). |
| C3 `838229501` | fix 시간 = page lock·버퍼 할당+디스크 읽기(`pgbuf_claim_bcb_for_fix`)·latch 대기(`pgbuf_latch_bcb_upon_fix`의 `pgbuf_block_bcb` 앞뒤) 구간만 | 직렬 q13 `fetch_time` 14675 → 1585, s21 933 → 197. |

게이트(optdebug `~/optdebug/CUBRID-trace-overhead`, PR=8137 ref, 컨테이너): CTP sql 17510/17510, medium 975/975, shell `cbrd_27599` 1/1(13 검사 OK), 코어 0.

### 측정 (g2: 같은 lane에서 base→c2→c3 순서를 lane마다 돌려 가며, 43 질의 × 5라운드 중앙값; CTP와 동시 실행)

| 설치 | T/P 중앙값 | T/P 최댓값 | S/P 중앙값 | ΣT/ΣP | ΣS/ΣP | P 변화(base 대비 중앙값) |
|---|---|---|---|---|---|---|
| base | 1.156 | 1.653 (s05) | 1.187 | 1.183 | 1.158 | — |
| c2 | 1.054 | 1.194 (s07) | 1.074 | 1.073 | 1.052 | 0.994 |
| c3 | 1.056 | 1.254 (q03) | 1.074 | 1.063 | 1.049 | 0.967 |

최악 사례 T/P: s04 1.61 → 1.24, s21 1.53 → 1.18, s05 1.65 → 1.16, s20 1.44 → 1.16, q03 1.36 → 1.25.
세션 간 영향(g3, c3): (c)/(b) = 0.997 / 0.937 → 없음. 설계 3(세션 단위 게이트)은 넣지 않는다.

### 남은 비용 (m5: c3에서 s04 1.18, s21 1.20, q03 1.14)

lock 접두 명령 뒤 샘플 0, vdso 0. 남은 것은 (1) 행마다 하는 trace 집계 — px scan의 `read_fixes`/`add_scan_fixes`(s04 추가 사이클의 51 %), `scan_next_scan_local`; (2) rdtsc 쌍(btree 타이머, 행 단위) 2 %; (3) 아직 외부 호출인 `perfmon_pbx_fix/unfix`, `perfmon_mvcc_snapshot` 2~3.7 % → C4에서 헤더 인라인.

### C4 (perfmon 이벤트 헬퍼 헤더 인라인, `4934222c1`) — 측정 결과 없음 → 폐기

g4(c3 vs c4, 같은 lane, CTP 동시 실행으로 소음 큼): T/P 중앙값 c3 1.050 / c4 1.046, S/P 1.046 / 1.067. 차이가 소음 안이고 핫 함수 본문이 커진다(`pgbuf_fix_release` +2165 B, `pgbuf_unfix` +1185 B, CC-08 배치 위험). 채택하지 않는다.

## 채택 (2026-10-12)

채택 기준(Q4)에 따라: c2·c3·c4는 T/P 중앙값 1.054 / 1.056 / 1.046으로 ±3 % 안의 동률 → diff가 가장 작은 **C1 + C2** (`e5e7ef30d`, `9f09ba92c`)를 채택한다. C3(fix 시간 = 대기 시간)는 의미 변경의 대가로 합계 1 %p뿐이라 빼고, C3/C4는 브랜치 `trace-overhead-c3c4`에 기록으로 남긴다. 브랜치 `trace-overhead`는 9f09ba92c로 되돌렸고, 이 상태의 optdebug 빌드(11.5.0.2659-9f09ba9)로 다시 돌린 게이트(g5): CTP sql 17510/17510, medium 975/975, shell cbrd_27599 1/1(13 검사 OK), 코어 0.

결과: `SET TRACE ON` 비용 중앙값 15.6 % → 5.4 %(합계 18 % → 7 %), `@collect_exec_stats` 19 % → 7 %, plain 성능 변화 없음, trace 값(fetch/ioread/rows/readrows/readkeys) 동일, 세션 간 영향 없음. 남은 5 %는 행 단위 trace 집계(PostgreSQL `EXPLAIN ANALYZE`의 tuple당 시계 2번과 같은 구조)와 btree 타이머의 rdtsc 쌍이다.

## PostgreSQL 기준과 분해 측정 (2026-10-12)

PostgreSQL 18.6, 같은 호스트·같은 SF10, 같은 43 질의·lane·5라운드 방식(`.git_ignored_dir/scratch/pg-tpch/summary.md`, s06은 상관 부질의 캐시가 없어 2라운드 후 제외, 42 질의): `EXPLAIN (ANALYZE, BUFFERS)` A/P 중앙값 1.058, 최대 1.347, 합 1.156; TIMING OFF N/P 중앙값 1.034. 같은 42 질의에서 CUBRID base T/P 1.146, c2 1.056.

분해 측정 g6 (`.git_ignored_dir/scratch/trace-perf/g6/summary.md`, 설치 `CUBRID-trace-ablate` = 9f09ba92c + 환경변수 `CUBRID_TRACE_ABLATE`, 7 lane 동시, 설정 순서 lane마다 회전):

| 설정 | 뜻 | T/P 중앙값 | 최대 | ΣT/ΣP | Tmin/Pmin 중앙값 |
|---|---|---|---|---|---|
| Z | C1+C2 그대로 | 1.061 | 1.297 (q03) | 1.065 | 1.061 |
| K1 | trace가 perfmon watch를 켜지 않음(trace fetch 값 0) | 1.018 | 1.194 (q17) | 0.987 | 1.016 |
| K2 | 행 단위 trace 집계 없음 | 1.038 | 1.241 | 1.070 | 1.048 |
| K12 | 둘 다 | 1.008 | 1.362 (q01, 소음) | 1.036 | 1.002 |
| X | `extended_statistics_activation=0` | 1.033 | 1.188 | 1.039 | 1.037 |

남은 6 % 중 약 4 %p가 perfmon watch(서버 전역 통계 수집) 몫, 약 2 %p가 행 단위 집계 몫이다. K1은 trace가 읽는 9개 통계까지 끈 상한이므로 trace-lite(9개만 스레드별로 집계)의 실제 값은 K1과 Z 사이다.

C2의 메모리 문제(사용자 지적): `SET TRACE ON`, `@collect_exec_stats`(`session_add_variable`), `cubrid statdump`(`smnt_server_start_stats`)가 모두 `perfmon_start_watch`로 전역 `n_watchers`를 올리므로, 누군가 보는 동안 통계를 기록한 모든 스레드가 86 KB를 할당하고 서버 종료까지 들고 있다(develop에는 없음, 상한 entry 수 4314 = 372 MB). trace-lite는 trace에서 이 경로를 없앤다.

TSC 확인(`.git_ignored_dir/scratch/tsc26512/results.md`): C1+C2 optdebug 서버와 SA 모두 `power_Savings` 0, `cpu_Clock_rate` 2099991300(공칭 2.1 GHz 대비 -0.0004 %). CBRD-26512 재현 SQL: CS trace/wall 0.986~0.987, SA csql 표시 시간 2.39~2.43 s / wall(프로세스 시작 포함) 2.72~2.78 s → 과대 표시 없음. SA는 SHOW TRACE가 원래 NULL(`qexec_set_xasl_trace_to_session`이 SERVER_MODE 전용). 같은 질의를 trace 켜고 CS로 돌리면 base 4.1~4.3 s, C1+C2 3.0 s. 옛 코드는 cpu0의 "cpu MHz"(2098~2902 MHz)를 읽으므로 이 호스트에서 TSC를 켜면 0.72~1.0배로 표시됐을 것이고, 26512의 3~4배는 "cpu MHz"가 0.5~0.7 GHz일 때의 값이다.

## 최종: C1 + trace-lite, CBRD-27604 (2026-10-12)

사용자 결정으로 C2를 빼고 trace를 perfmon watch에서 분리했다. worktree `~/dev/cubrid-worktree/trace-lite`, 브랜치 `trace-lite`: 6820f5ece(CBRD-27599 후속, 병렬 fetch_time 합산) → 623c7efd6 C1 → a7527013b trace-lite → cdc050d31 root 읽기 수정. JIRA CBRD-27604 (Improve, cubrid-todo, CBRD-26512·27599 Relates, 26512에 댓글).

- trace-lite: `SET TRACE ON`이 `perfmon_start_watch`를 부르지 않는다. trace가 읽는 9개 통계만 `thread_p->on_trace`인 스레드가 tran_stats/m_px_stats에 일반 덧셈으로 센다(`perfmon_inc_stat_for_trace`, `pgbuf_fix_release`의 `is_trace_only`, 로컬 갱신 조건 3곳). develop에서 trace watch가 `SET TRACE OFF` 뒤에도 접속 종료까지 남던 문제도 없어진다(gdb `n_watchers` base 1, lite 0).
- 1차 게이트에서 찾은 develop 결함: 병렬 subquery root는 run_jobs가 자기 배열을 tran_stats로 넘기기 전에는 배열만, 후에는 tran_stats만 읽어, 전환을 걸친 HASHJOIN/UNION/위 SELECT 줄에 질의 전 tran_stats 값이 더해졌다. develop은 SHOW TRACE(DONT_COLLECT_EXEC_STATS)의 watch 재시작 memset이 가렸다. SHOW TRACE 없이 두 문장을 이어 실행하면 base도 HASHJOIN 29547 → 35191. cdc050d31: root는 tran_stats + 자기 배열을 읽는다. 같이 `xboot_unregister_client`가 슬롯을 지운다.
- 게이트(optdebug, TC_REF=tc/pr-8137): CTP sql 17510/17510, medium 975/975, cbrd_25748+cbrd_25717 15/15, cbrd_27599 13/13, core 0. statdump 동시 실행 trace 값 같음, 병렬 fetch_time > 0. 증거 `.git_ignored_dir/scratch/trace-lite-gates/r2/`.
- 측정(release, 43 질의, 7 lane). 증거 `.git_ignored_dir/scratch/trace-perf/g7/`, `g8/`, `g9/`; 모두 다른 작업의 CTP로 load1 중앙값 48~76.

| 측정 | B T/P 중앙값 | L T/P 중앙값 | B ΣT/ΣP | L ΣT/ΣP | P_L/P_B |
|---|---|---|---|---|---|
| g7 (B, C1+C2, L 회전) | 1.105 | 1.019 | 1.159 | 0.956 | 순서 교란 |
| g8 (B, L 한 번씩) | 1.119 | 1.039 | 1.195 | 1.107 | 순서 교란(먼저 돈 쪽 15~20 % 느림) |
| g9 블록 1 / 2 (lane마다 B L B L / L B L B) | 1.109 / 1.126 | 1.024 / 1.020 | 1.155 / 1.140 | 1.034 / 1.036 | 중앙값 0.978, 기하평균 0.949 |

PostgreSQL 18.6 EXPLAIN (ANALYZE, BUFFERS) 1.058(합 1.156)보다 낮다. 알려진 한계: 질의를 처리한 서버 스레드의 `on_trace`는 다음 질의 시작까지 남는다(develop과 같음, trace 값 영향 없음). `@collect_exec_stats`·statdump 비용은 C1 몫 외에는 develop 그대로(후속 이슈).
