# cas-merge 귀속 프로브 — 현 head 성능 귀속 재채집 (wf218, 2026-09-09)

- 티켓: [브레인스토밍 2 — cpp-perf-rules 렌즈](https://github.com/xmilex-git/workspace/issues/218), 스펙: [프로브 스펙 코멘트](https://github.com/xmilex-git/workspace/issues/218#issuecomment-5594773683)
- 실행: Sonnet 서브에이전트(리드 스펙 고정, 워커 실행). 워커의 `report.md` 쓰기는 하네스 훅이 막아 워커 답신과 원자료로 리드가 이 문서를 조립했다.
- 성격: CONTEXT.md의 **귀속 프로브**. A/B 판정·accept/reject 근거가 아니며, [cpp-perf-rules 관점](../cas-merge/perf-rules-review.md) 후보의 기대 효과 계수와 측정 계획 시딩에만 쓴다. 등급 **INDICATIVE**(perf 부착·비단독 호스트 이력).
- 원자료: 툴링 리포 `.git_ignored_dir/scratch/wf218-probe/`(`l1-layout/`, `l2-perf/`, `l3-counters/`, `l4-c2c/`, `l5-memory/`, `l7-statdump/`, `l8-connect/`, `logs/`, `conf/`, `scripts/ConnHold.java`, `PROGRESS.md`). perf.data 약 8GB.

## 0. 출처

| 항목 | 값 |
|---|---|
| 빌드 | `/home/cubrid/release/CUBRID-wf218-probe` = `CUBRID-wf226-integrated` 사본, `11.5.0.2812-30937a9`(release/RelWithDebInfo), `libcubrid.so.11.5` sha256 `6bd74c2e77ed62bc3326b9be0355f5a0b38a481feff1c4908ade3255e5ac110f`. PR head `702d62c6a`까지 22커밋은 cold path만 변경 |
| JDBC | 설치본에 `jdbc/`가 없어 `CUBRID-wf222-final/jdbc/` 11.4.0.0076 jar 보충(편차) |
| DB | golden `ycsb_g`(`/home/cubrid/wf125-ycsb-db`, 10M rows) → `copydb` → `/home/cubrid/wf218-probe-db/ycsb`. golden은 어떤 `databases.txt`에도 없어 수동 등록(read-only) |
| conf | #125 + G2: `data_buffer_size=4G, log_buffer_size=2G, vacuum_worker_count=50, max_clients=200, data_buffer_neighbor_flush_pages=0, cubrid_port_id=1523, checkpoint_every_size=256G, checkpoint_interval=120min`; 브로커 `BROKER_PORT=33000, SQL_LOG=OFF, MIN/MAX_NUM_APPL_SERVER=120, DIRECT_HANDOFF=ON`; query_editor OFF. L5′/L8은 `max_clients=1100`/`MAX_NUM_APPL_SERVER=1100` |
| 호스트 | Xeon Silver 4216 ×2소켓(32 CPU, SMT 없음), NUMA node0=0-15/node1=16-31, 커널 6.9.4, perf 4.18 |
| idle 게이트 | 시작 시 loadavg1 4.25 + 타 세션 CTP 컨테이너 가동 → 27분 대기 후 3.05~3.67에서 진행 |
| perf 권한 | `perf_event_paranoid=-1`, `kptr_restrict=0`, `nmi_watchdog=0`(사용자 설정) → 커널 포함 샘플·`--topdown -a`·`perf c2c` 정식 사용 |
| **체크포인트** | **전 레그 0회**(서버 이벤트 로그 리터럴 `checkpoint` 0건). "Flush victim candidates"는 체크포인트가 아닌 상시 페이지버퍼 스캔(C: count=0 공회전, A: 실제 victim flush)으로 구분 확인 → G2 conf 유효 |
| 워크로드 | `cubrid-perftools-internal/ycsb` `run.sh`, threads=100, zipfian, `workloadc`/`workloada`. 프로파일 레그 5M ops(L3 C는 15M, L4 C는 8M) |

## 1. 처리량·레이턴시 (INDICATIVE, 전건 Return=0)

Workload C — 독립 실행 3회(L2 5M / L3 15M / L4 8M ops):

| 지표 | median | MAD |
|---|---|---|
| Throughput (ops/s) | 118,887 | 6,495 |
| READ avg (µs) | 830.2 | 48.1 |
| READ p95 (µs) | 1,672 | 96 |
| READ p99 (µs) | 2,285 | 132 |

Workload A — 독립 실행 4회(L2/L3/L4/L7, 각 5M ops):

| 지표 | median | MAD |
|---|---|---|
| Throughput (ops/s) | 28,880 | 661 |
| READ avg / p95 / p99 (µs) | 714.8 / 2,941 / 6,067 | 81.9 / 1,105 / 374 |
| UPDATE avg / p95 / p99 (µs) | 6,126.6 / 20,559 / 25,463 | 164.4 / 584 / 504 |

#177 게이트(C 147,013 / A 29,063, gate-grade, perf 미부착)와의 차이는 perf 부착과 호스트 상태 때문이며 이 표는 게이트 값이 아니다. **A READ p99 6,067µs(MAD 374)**는 #177의 11,279µs보다 낮고 산포도 작다 — 체크포인트-조용 conf가 꼬리 오염원을 제거했다는 G2 결정의 첫 실측 근거.

## 2. L2 — dwarf 프로파일 상위 심볼과 호출자 분해

`perf record -e cycles:u --call-graph dwarf,16384 -F 499 -p <cub_server> -- sleep 30`(steady 20초 후). 편차: 두 레그 모두 perf가 `lost 80~82 chunks` 경고 → self%는 보존 샘플 기준 근사. C 커널 포함 10초 샘플은 타이밍이 빗나가 백그라운드 스레드만 잡혀 무효(A는 정상).

### 2.1 상위 self%

| 심볼 | C | A |
|---|---|---|
| `__pthread_mutex_lock` | 3.96 | **4.51** |
| `__memmove_evex_unaligned_erms` | **4.52** | 2.95 |
| `malloc` (+`_int_malloc`, `malloc_consolidate`, `_int_free`) | 4.09 (+3.13 consolidate) | 2.44 (+1.80 +1.34 +1.12) |
| `pgbuf_fix_release` | 2.11 | 2.22 |
| `lock_internal_perform_lock_object` | 2.95 | 1.78 |
| `lock_internal_perform_unlock_object` | 2.54 | 1.47 |
| `__tls_get_addr` | **1.85** | 1.39 |
| `mht_clear` | 1.32 | 1.04 |
| `__memset_evex_unaligned_erms` | — | 1.49 |
| `LZ4_compress_fast_extState`(로그 압축) | — | 1.30 |
| `pr_clear_value` | — | 1.08 |
| `cas_process_request` self | 0.82 | — |
| 커널 포함(A만 유효): `native_queued_spin_lock_slowpath` | — | 4.38 |

### 2.2 호출자 분해 (`-g caller,0.5,callee --percent-limit 0.3`)

| 심볼 | 워크로드 | 귀속 | 후보 |
|---|---|---|---|
| `__tls_get_addr` 1.85 / 1.39 | C / A | 0.3% 임계 위 유일 귀속 `csc_current` 0.31(C); 나머지는 32곳+ 호출 지점에 파편화(5,463 call site 서술과 정합). ld.so 경계에서 dwarf 호출자 일부 유실 | N1 |
| `__memmove` 4.52 / 2.95 | C / A | `cursor_copy_list_id` 2.00 / 0.93 + `qmgr_attach_first_page_copy` 1.90 / 0.95 — **두 16KiB 페이지 복사가 memmove의 86%(C)** | N9 (T2·T3) |
| `qmgr_attach_first_page_copy` children | C / A | **5.73 / 2.07**(malloc+memcpy+페이지 fix 포함) ; `cursor_copy_list_id` children 2.27 / 1.04 | N9 |
| `malloc` 4.09 / 2.44 | C / A | `cub_alloc` 2.35 / 1.30, 그중 **`db_cp_query_type_helper` 1.18 / 0.46**(execute마다 결과 메타데이터 `DB_QUERY_TYPE` 노드 복사); 나머지 파편화 | **P3**(불변 메타데이터 공유) 실측 근거, N7 |
| `__pthread_mutex_lock` 3.96 / 4.51 | C / A | `heap_classrepr_get` 0.54 / 0.74(←`heap_attrinfo_start` 0.33 / 0.39, `scan_start_scan` 0.31), `heap_classrepr_free` — / 0.43(←`heap_attrinfo_end` 0.38), `lock_internal_perform_unlock_object`→`lock_unlock_all` 0.39 / 0.50, `lock_delete_from_tran_hold_list` 0.35 / — . 합 1.28 / 1.67, 나머지 파편화(#177 미귀속 갭 부분 해소) | U3, U1 |
| `lock_internal_perform_lock_object` 2.95 / 1.78 | C / A | C: **`lock_find_my_holder_entry`(inlined) 1.97** — 트랜잭션 보유 목록 선형 탐색이 락 비용의 2/3. A: `lock_object`←**`xcache_find_xasl_id_for_execute` 0.96**(실행 시 클래스 IS 락), `do_execute_select` 0.49 / `do_execute_update` 0.47 | U1 |
| `mht_clear` 1.32 / 1.04 | C / A | `logtb_tran_clear_update_stats`(inlined) 0.68 / 0.50 ← `logtb_complete_mvcc` ← `log_commit_local` | U2 |
| `cas_process_request` children | C / A | 96.2 / 81.2 — 요청 루프가 세션 스레드 시간의 거의 전부 | — |

## 3. L3 — 카운터와 TMA L1

`perf stat -p <cub_server>` user-only, steady 30초 ×3, **median**(C 3회는 거의 동일; A는 cycles 333.4/376.6/388.0 B로 변동). 12이벤트 그룹이라 PMU 멀티플렉싱 33~50% 스케일링(배율은 반복 간 일관) — 절대치는 추정치.

| 카운터 (30초, median) | C | A |
|---|---|---|
| cycles:u | 859.2 B | 376.6 B |
| instructions:u | 500.4 B | 148.8 B |
| **IPC** | **0.58** | **0.40**(0.38~0.45) |
| cache-references / misses | 29.67 B / 2.309 B (**7.76%**) | 10.98 B / 1.297 B (**11.8%**) |
| branch-instructions / misses | 119.9 B / 2.083 B (**1.74%**) | 33.74 B / 1.158 B (**3.43%**) |
| uops_issued.any / uops_retired.retire_slots | 576.7 B / 521.4 B | 180.6 B / 154.5 B |
| int_misc.recovery_cycles | 13.25 B | 7.42 B |
| idq_uops_not_delivered.core | 1,925.6 B | 697.0 B |
| dsb2mite_switches.penalty_cycles | 8.80 B (1.0% of cycles) | 3.13 B (0.8%) |
| cycle_activity.stalls_mem_any | 422.2 B (49.1% of cycles) | 220.0 B (58.4%) |

TMA L1(수동 공식, 4·cycles 기준, 3회 범위) vs `perf stat --topdown -a`(시스템 전역 20초; 대다수 코어 균일, 일부 코어는 타 프로세스로 이질):

| 슬롯 | C 수동 (3회) | C topdown -a | A 수동 (3회) | A topdown -a |
|---|---|---|---|---|
| Retiring | 15.2% | 15.6~16.1% | 10.0~11.9% | 13.3% |
| Bad speculation | 3.1~3.2% | 3.4~3.7% | 3.5~4.3% | 4.7% |
| **Frontend bound** | **56.0~56.1%** | **43.1~44.5%** | **44.8~53.0%** | **38.2%** |
| Backend bound | 25.6~25.7% | 35.7~37.7% | 30.8~41.7% | 43.8% |

두 방법 모두 **frontend-bound가 최대 슬롯**이고 retiring은 10~16%다. 프로세스 한정 수동 공식(FE 56%)과 시스템 전역(FE 43%)의 FE/BE 배분 차이는 32코어 평균 희석과 공식 근사 차이로 보고 한쪽만 신뢰하지 않는다. A의 backend-bound는 반복 간 변동(30.8→41.7%)이 커 A는 방향만 취한다. DSB→MITE 전환 페널티는 cycles의 1%에 그치므로 FE 병목의 주범은 DSB 스위치가 아니라 **I-cache/iTLB 미스·분기 resteer**로 좁혀진다(MEAS-02 3단계 후속: `icache_64b.iftag_stall`, `icache_16b.ifdata_stall`, `itlb_misses.walk_pending`, `frontend_retired.*`). 이는 327MB `libcubrid.so`·5,463 GD-TLS 호출·`-finline-functions` 코드 팽창과 정합하며 CC-08(레이아웃 민감성)·BR-08/CC-05(콜드 코드 분리) 축의 우선순위를 올린다.

## 4. L4 — `perf c2c` HITM (COH-02)

`perf c2c record -a -- sleep 20`, C(8M ops 실행 중)와 A(5M ops 실행 중).

| 지표 | C | A |
|---|---|---|
| LLC miss → remote cache HITM | **34.0%** | 24.3% |
| LLC miss → remote DRAM / local DRAM | 54.8% / 11.2% | — |
| 공유 캐시라인 수 | 47,032 | — |

상위 HITM 캐시라인(C; A도 동일 계열 재현):

| # | 라인 실체 | 심볼(오프셋) | 판정 |
|---|---|---|---|
| 0 | **QMGR 질의 엔트리** 상태 필드 | `qexec_intprt_fnc`(0x0), `qmgr_is_query_interrupted`·`xqmgr_end_query`·`qmgr_check_dblink_trans`·`xqmgr_execute_query`·`qmgr_get_current_query_id`(0x20), 뮤텍스(0x38) | 질의 엔트리 메모리가 전역 풀에서 재사용되며 코어 사이를 왕복(COH-12 "transfer" 결함형). 선존 |
| 1 | **classrepr 캐시 엔트리** 뮤텍스+필드 | `__pthread_mutex_lock/trylock/unlock`(0x10~0x20), `heap_classrepr_get`(0x38) | U3 확증 — 모든 세션이 `usertable` 엔트리 하나를 두드림 |
| 2 | **pgbuf BCB** | `pgbuf_fix_release`(0x2c, 70%), `pgbuf_unfix`(0x38, 23%) | 핫 인덱스 페이지 BCB. 선존 |
| 3 | **xcache 엔트리** | `SHA1Compare`·`xcache_compare_key`·`xcache_find_xasl_id_for_execute`·`xcache_entry_get_entrysize` — 한 엔트리의 SHA1/size 필드에 43~56% | 100세션이 같은 plan 엔트리를 fix/unfix. **P6 공유 준비 객체 설계의 COH-04 입력**: 불변 키(SHA1·size)와 가변 카운터(fix count·시각)를 다른 라인에 |
| 4 | QMGR 임시파일 뮤텍스 | `__pthread_mutex_lock`(0x8, 96%) ← `qmgr_create_new_temp_file`(`query_manager.c:3584`) | 선존 |
| 5, 7+ | 커널 `switch_mm_irqs_off`; 스캔 디스크립터(`scan_open_index_scan` `scan_manager.c:3483/3575`, `scan_close_scan` `:1446`); A에는 `futex_wake`·`native_queued_spin_lock_slowpath`·`_raw_spin_lock` 라인 추가 | — | 선존 |

C/A 요약치: Load Local HITM 129,376 / 50,258, Remote HITM 78,120 / 30,558, LLC miss→Local DRAM 11.2% / 21.4%, →Remote DRAM 54.8% / 54.3%.

부수 관찰(A, 라인 #9): `logtb_find_client_type`(`log_impl.h:1275`)과 `pgbuf_fix_release`가 **같은 캐시라인 오프셋**에서 샘플됨 — 진단 미완, 기록만.

**상위 20에 없음**: `lk_res`(락 리소스 엔트리), `area_alloc`/`LF_BITMAP`, `session_state`, `csc`, `tp_domain_cache_lock`. → N12(AREA)는 이 프로파일에서 종결 방향(S9 현행 유지), U1의 경합 실체는 캐시라인 HITM보다 뮤텍스 대기·보유 목록 탐색 쪽.

## 5. L5/L5′ — 메모리 5단계와 연결당 기울기

`cub_server` `smaps_rollup`(kB), 10초 간격 ×3 중앙값. 단일 서버 세션(S1→S5 사이 재시작 없음). **주의**: S1 직후 L2-C 실행이 끼어 S2−S1에는 페이지버퍼 채움(≈3.2GB)이 섞였다 — 연결당 기울기는 아래 표시한 차분만 유효.

| 단계 | Rss | Pss | Anonymous | 스레드 수 |
|---|---|---|---|---|
| S1 fresh boot(200-conf) | 3,435,456 | 3,431,511 | 3,423,244 | 228(부트 일시 스레드 포함) |
| S2 100 유휴 연결(L2-C 이후) | 6,609,304 | 6,605,349 | 6,592,776 | 169 |
| S3 100 연결 + READ/UPDATE 1회 prepare·execute | 6,644,708 | 6,640,758 | 6,628,016 | 169 |
| S4 A 실행 steady | 6,664,396 | 6,660,440 | 6,647,640 | 170~171 |
| S5 전 연결 종료 +10초 | 6,634,700 | 6,630,755 | 6,617,980 | 69 |
| S2′ 1,000 유휴 연결(1100-conf, 재시작 직후) | 3,947,200 | 3,943,903 | 3,932,900 | 1,229 |
| S3′ 1,000 연결 + prepare·execute | 4,376,672 | 4,373,379 | 4,361,264 | 1,229 |
| S5′ 전 연결 종료 | 4,061,732 | 4,058,445 | 4,046,324 | 229 |

유효한 연결당 계수:

| 계수 | 값 | 의미 |
|---|---|---|
| 스레드 | **+1/연결**(1,229 = 229 + 1,000) | 접속당 스레드 확인 |
| (S3′−S5′)/1,000 | **315 kB/연결** | 연결 종료 시 실제 반환되는 세션 메모리(하한; allocator 캐시 잔류 제외) — TLS 240KiB + `client_session_context` 19.4KiB + 출력 버퍼 80KiB(≈340KiB)와 정합 |
| (S3−S2)/100, (S3′−S2′)/1,000 | 354 kB, 429 kB/연결 | 문장 prepare·execute 증분(상한; xcache·페이지버퍼 공유 증분 포함) |
| (S2′−S1)/1,000 | 512 kB/연결 | 유휴 연결 증분 **추정**(1100-conf 부트 기준선 미채집 — S1′ 없음, conf 차이로 과대 가능) |
| S5′−S2′ | +114 MB | 1,000 연결이 남긴 공유 잔류(xcache·페이지·allocator) |

R2(로그 버퍼 lazy)·R3(출력 버퍼)·S2/S9(워크스페이스 lazy)의 기대 효과 계수는 이 315~512 kB/연결 안에서 각 항목의 비중으로 산정한다. 1,000연결에서 세션 메모리 ≈ 315~512 MB.

numastat(MB): S1 부트 직후 node0 448 / node1 2,900(부트 스레드가 node1에서 first-touch — 로그 버퍼 2G 등), C 실행 중 2,862 / 3,624, A 실행 중 3,073 / 3,495. Heap(glibc arena) 62~64MB. 편중은 부트 시점 구조에 한정, 실행 중에는 45/55 — PAR-09 후보는 게이트 산포 원인으로만 기록.

## 6. L8 — 접속 수립 지연 (브로커 핸드오프 직렬화)

`ConnHold` 도구, JDBC 연결 N개를 1스레드 순차 / 16스레드 병렬로 수립. 연결당 지연(ns→ms).

| N × 스레드 | 벽시계 | p50 | p90 | p99 | max | 처리율 |
|---|---|---|---|---|---|---|
| 100 × 1 | 260 ms | 1.31 ms | 1.73 | 9.53 | 65.8 | 385/s |
| 100 × 16 | 196 ms | **9.32 ms** | **100.8** | 102.0 | 102.5 | 510/s |
| 1,000 × 1 | 1,244 ms | 0.98 ms | 1.33 | 2.00 | 66.2 | 804/s |
| 1,000 × 16 | 704 ms | **9.07 ms** | 9.48 | **96.7** | 97.9 | 1,420/s |

16배 병렬이 처리율을 1.3~1.8배만 올리고 연결당 p50은 7~9배 늘어남 → **핸드오프 경로가 ≈1 ms 서비스 시간의 단일 서버**(dispatch 스레드 + `config_mutex` + 채널 `request_mutex`)임을 실측. 병렬 시 p90~p99의 **≈100 ms 계단**은 대기 경로의 고정 지연(peek 엔진 `epoll_wait` 1초 타임아웃 스윕 또는 admission 30ms 폴링의 배수)으로 추정 — X1 후보의 측정 입력, 원인 확정은 후속. 브로커 `#CONNECT` 2,000→4,200, `#REJECT` 0.

## 7. L7 — statdump 워처 게이트

A 실행 25초 시점에 `cubrid statdump -c ycsb` 1회: 265개 항목이 즉시 비0이지만 값이 작다(`Num_tran_commits=390`, `Num_query_selects=452`, `Num_object_locks_acquired=1,334`, `Num_data_page_fetches=4,316` — 처리량 27.6k/s 기준 약 15ms 분량). 두 해석을 병기한다: (a) 리드 — 워처 부착 RPC와 읽기 RPC 사이의 창만 누적된 것으로 "카운터는 `n_watchers>0`일 때만 누적"이라는 코드 사실과 정합, (b) 워커 — #177의 "전부 0"이 재현되지 않았고 앞선 접속이 워처를 올려 뒀을 가능성도 배제 못 함. 어느 쪽이든 `-c` 단발은 부팅 이후 누적치가 아니며, 게이트 계측은 `-i` 모드로 한다. `statdump -i 5` 첫 반복은 전부 0(델타 기준선), 둘째 반복 `Num_tran_commits=137,802/5s ≈ 27.6k/s`(A 처리량과 일치), `Num_object_locks_acquired=413,647/5s`, `Num_log_append_records=199,954/5s` — 델타 기구 정상.

**이상값**: 둘째 반복의 `Num_object_locks_time_waited_usec=1,648,912,272,933,097`(5초 창에 약 5만 년어치 µs) — 미초기화/오버플로/단위 오류 의심, 원인 미추적. 상류 확인 후보로 기록.

## 8. L6 prepare-churn

**생략**. `jdbc.cachestatements`(기본 true) 속성으로 `read()`/`update()`가 매번 새 PreparedStatement를 만들고 닫는 설계까지는 ≤30줄로 가능했으나, 공유 하네스 체크아웃(`~/dev/cubrid-perftools-internal/ycsb`)의 `lib/core-0.4.0.jar`·`lib/jdbc-binding-0.4.0.jar`가 워커가 손대기 전부터 커밋 대비 수정(uncommitted) 상태여서 Maven 재빌드·patch-revert가 원상을 보장하지 못한다고 판단해 안전 우선으로 생략했다. 시간 예산 지시도 같은 방향. 하네스 옵션은 구현 노력의 진입 게이트에서 추가한다(G9 유지).

## 9. 편차·미측정

- dwarf 샘플 유실(`lost 80~82 chunks`; C 4.7GB/296K 샘플, A 2GB/123K 샘플) → L2 self%는 근사. 다음엔 `-F 249` 또는 `--call-graph dwarf,8192`.
- C 커널 포함 10초 샘플 타이밍 실패(무효), A는 유효.
- **툴링 갭**: `cubrid broker start`도 출력이 파이프에 물리면 hang(데몬은 정상 기동, 감시 셸만 멈춤). `cubrid-server-control` 스킬은 `cubrid server`만 감싸므로 워커가 `scripts/broker-ctl.sh`를 새로 써 대체 — 스킬 확장 후보.
- A 4회 실행 사이에 copydb 재복사를 생략(S1→S5 연속 세션 유지 목적) → §1의 A 수치는 누적 갱신된 DB 위에서 측정. S3의 UPDATE가 golden 사본 1행을 덮어씀(스펙대로). 어느 것도 gate-grade 수치가 아니다.
- S2−S1은 L2-C 개입으로 연결당 계수에 부적합. 1100-conf 부트 기준선(S1′) 미채집. numastat 보충 채집은 원 세션 종료 후 별도 재시작 세션(pid 583560)에서 loadavg1≈21(비유휴) 상태로 수행 — 비율만 취한다.
- L5′ 1,000연결·S4/S5의 numastat 미채집(애드엔덤이 원 세션 종료 후 도착).
- `statdump` 이상값(§7) 원인 미추적.
- `__tls_get_addr`·`__pthread_mutex_lock`·`malloc` 호출자 분해는 0.3% 임계 아래로 파편화된 부분이 커서 합이 self%에 못 미침. 다음엔 `--percent-limit 0.1` + 심볼 필터.
- 처리량은 perf 부착·호스트 이력 때문에 INDICATIVE. 게이트 판정에 쓰지 않는다.
- 접속 지연의 100ms 계단 원인 미확정.
- 산출물 8GB(perf.data)와 프로브 설치본·DB 사본은 보존 중 — 삭제는 리드 결정.
