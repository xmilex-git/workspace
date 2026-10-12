# SHOW TRACE 숫자 정확성 전수조사 — 11.5 시작 지점 대비 현재

추적: xmilex-git/workspace#428 (닫음) → JIRA CBRD-27599 "Trace and exec statistics lose or miscount what parallel workers count" (2026-10-11, 담당 cubrid-todo). 용어: GLOSSARY.md "trace 정확성 전수조사".

- 11.5 시작 지점: `91be5b11f` (release `~/release/CUBRID-sha-91be5b11f`, 11.5.0.1779-91be5b1)
- 현재: `a9940d67a` (release `~/release/CUBRID-sha-a9940d67a`, 11.5.0.2655-a9940d6) = origin/develop 2026-10-11
- DB: TPC-H SF10, 각 빌드로 따로 적재 (`~/databases/trace115/{base,cur}`)
- 엔진 워크트리: `~/dev/cubrid-worktree/trace-accuracy`

## 판정 기준

trace 진실값: 같은 실행의 statdump 증가량(전역), `SHOW EXEC STATISTICS` 증가량(세션), 같은 조건의 SQL COUNT.
정상이면 trace ≤ 세션 ≤ 전역. 실측 차이는 후보를 고르는 데만 쓰고, 결함은 코드에서 원인을 찾아 확정한다.
병렬 표기: 바깥 줄 = 워커 합(횟수 합계, 시간은 경과 시간), 괄호 줄 = 워커별 `min..max`.

## statdump(전역 카운터) 감사 — 정적

| 항목 | 결과 |
|---|---|
| fetch 증가 지점 | `pgbuf_fix_release` 한 곳(`page_buffer.c` "Record number of fetches"), `ATOMIC_INC_64` 로 전역에. 11.5 시작 지점과 같은 구조. CBRD-26425 lock-free fast path(`goto fast_path`)도 이 지점 앞으로 합류한다. |
| ioread 증가 지점 | 디스크 읽기 두 곳(`pgbuf_claim_bcb_for_fix` 경로, DWB/파일 읽기 경로). 11.5 시작 지점과 같은 구조. |
| 세는 조건 | `perfmon_is_perf_tracking()` = 감시자(statdump, `SET TRACE ON`, `@collect_exec_stats`)가 하나라도 있을 때만. |
| fetch 아닌 페이지 | membuf(메모리 temp 버퍼), 로그 페이지, DWB — 두 빌드 공통으로 `pgbuf_fix` 를 거치지 않는다. |
| 세션 통계만 빠지는 경로 | `perfmon_add_at_offset`: 병렬 스레드(`m_uses_px_stats`)인데 `m_px_stats == NULL` 이면 전역에만 더한다(주석 "need to check later"). 이 스레드의 fix 는 trace·세션에서 빠지고 statdump 에만 잡힌다. |

## 결함 목록

| # | 영역 | 증상 | 원인 | 상태 |
|---|---|---|---|---|
| C1 | 병렬 heap scan | SCAN 줄 `rows` = `readrows` (Q6 cur `rows: 59986052`, base `rows: 1139264`; s08·s09 도 같은 증상, 뒤 GROUPBY readrows 16705151 / ANALYTIC rows 7595510 가 실제 통과 행) | `px_scan_slot_iterator.cpp` `next_qualified_slot_with_peek`: `qualified_rows++` 가 `ev_res != V_TRUE` 검사보다 앞(CBRD-25447, 2025-10-28). list 반복자·직렬 `scan_next_heap_scan` 은 참일 때만 센다. | 확정 |
| D1 | 병렬 스캔 + NL 안쪽(scan_ptr) | 바깥 SCAN 줄 `fetch` 가 수십~수백, `readrows: 0, rows: 0`; 루트 SELECT fetch 에 워커 몫이 빠진다. 안쪽 스캔 줄은 맞다. q03: trace 111,192 / 전역 34,504,078 (안쪽 29.16M + 5.07M). q02·q04·q12·q14·q16·q21·s05·s21 같은 유형. trace 를 켠 세션 통계에도 빠진다(q03 111,196). | scan_ptr 가 있으면 `manager::next()` 가 끝에 `pre_execution_info::apply_pre_execution_info (m_xasl)`(`px_scan_pre_execution_info.cpp:138-149`, MERGEABLE_LIST·BUILDVALUE_OPT)을 불러 바깥 노드부터 scan_ptr 체인 전체의 `s_id.status` 를 `S_ENDED` 로 직접 바꾼다. 그 뒤 executor 의 `qexec_end_scan` → `scan_end_scan` 은 `S_ENDED` 라서 바로 반환(`scan_manager.c:5201`)하므로 `scan_end_parallel_heap_scan` → `manager::end` → `merge_stats`(트랜잭션 통계·`scan_stats` 합산)가 실행되지 않는다. `scan_close_parallel_heap_scan`(`px_scan.cpp:262-287`)은 워커별 저장소(`add_stats`)만 채운다. gdb(작은 DB, optdebug a9940d67a): NL 있는 Q2·Q3 에서 `merge_stats`·`scan_end_parallel_heap_scan` 0회, 단일 테이블 Q1 은 `qexec_next_scan_block` S_END → `scan_end_scan` → `manager::end` → `merge_stats` 1회(`gdb-nl/REPORT.md`). 도입: CBRD-26522 `a4b37fd80`(2026-03-10). | 확정 |
| D2 | 병렬 정렬 (GROUPBY/ORDERBY/ANALYTIC) | 바깥 줄 `page` 가 워커 합이 아니라 리더 몫(또는 0): s08 GROUPBY 39003 vs 워커 38481..44416, s12 ORDERBY 0 vs 46853..85978, s09 ANALYTIC 25151 vs 18312..34634, q16 GROUPBY 106 vs 2547..3206. 정렬 워커 fetch 도 SELECT 에서 빠진다(s08 trace 0.93M / 전역 2.21M). | 정렬 워커(`external_sort.c` `sort_listfile_execute`)는 trace 가 켜지면 자기 통계 배열을 만들고(1621행 `perfmon_initialize_parallel_stats`), 끝에 정렬 page·ioread 만 꺼내 min/max 용으로 남긴 뒤 배열을 리더에 합치지 않고 버린다(1719-1722행 `perfmon_destroy_parallel_stats`). `sort_end_parallelism` 은 `px_min/max_*` 만 채우고, 바깥 줄 `orderby/groupby/analytic_pages` 는 리더 자신의 `PSTAT_SORT_NUM_DATA_PAGES` 차이로 계산된다. hash join 은 `perfmon_merge_parallel_stats_to_tran_stats` 로 합친다(비교 기준). | 확정 |
| D3 | ORDERBY page/ioread | 앞선 정렬과 같은 값이 다시 찍힌다: q18 최상위 ORDERBY(624행) page 172243 / ioread 205021 = 서브쿼리 GROUPBY 값 = 서브쿼리 ORDERBY 값; q13 최상위 ORDERBY 11253 = 서브쿼리 GROUPBY 11253. | `qexec_orderby_distinct` 는 `orderby_filesort` 가 이미 참일 때만 기준값(`old_sort_pages/ioreads`)을 읽는데(4119행), 이 플래그는 정렬 함수 안(`qexec_orderby_distinct_by_sorting` 4189행)에서 처음 켜진다 → 첫 실행은 기준값 0, ORDERBY page/ioread = 트랜잭션 누적 정렬 page. 11.5 시작 지점도 같은 코드(base q18 최상위 ORDERBY 429484 = 서브쿼리 GROUPBY 429484) — 병렬 무관, 기존 결함. | 확정 |
| D4 | GROUPBY readrows (hash aggregation 이 넘칠 때) | 입력 행보다 적다: q18 병렬 59,976,334 / 직렬 59,972,323 vs 입력 59,986,052; q13 병렬 −1,096, 직렬은 정확. 병렬 전용 아님. | (수정 중 코드로 확정, 처음 추정은 틀림) 한 그룹이 hash 표에서 두 번 이상 밀려나면(LRU eviction, 끝에 남은 그룹의 dump 포함) partial list 에 그 그룹 항목이 여러 개 생긴다. partial list 를 정렬하며 같은 키를 합치는 `qexec_hash_gby_put_next` 는 누산기만 합치고 뒤 항목들의 `tuple_count` 를 버린다 → `input_recs += hvalue->tuple_count`(`qexec_gby_get_next`) 가 첫 항목 몫만 센다. 밀려날 때마다 첫 행은 정렬 목록으로 가서 `input_recs++` 로 세므로 "+1 누락" 은 아니었다. `readrows` 항목은 CBRD-26976(2026-08-06)에서 생겨 11.5 시작 지점과 비교 불가. | 확정 |
| D5 | JSON trace: 파티션 테이블 병렬 스캔 | text 에는 `(parallel workers: N, ...)` 줄이 있는데 JSON 에는 `"parallel heap"` 객체가 없다(s15, s16). | text 는 `S_PARALLEL_HEAP_SCAN \|\| S_HEAP_SCAN` 이면 저장소를 출력(3600행), JSON 은 `S_PARALLEL_HEAP_SCAN` 만(3098행). 파티션 스캔은 마지막 파티션 뒤 타입이 `S_HEAP_SCAN` 으로 돌아간다. | 확정 |

## 정적 후보 (실측 확인 전)

| # | 위치 | 내용 |
|---|---|---|
| S1 | `xasl_merge_stats` (`xasl_iteration.cpp`) | 워커 복제 XASL 의 통계 합산이 `spec_list` 첫 spec 만 본다(`spec_list->next`, `merge_spec` 누락). `groupby_stats.read_rows`, `orderby_stats`, `analytic_stats`, `func_stats`, `elapsed_hash_build` 를 합치지 않는다. |
| C2 | `perfmon_add_at_offset`, px_scan·hash join 워커 | 워커는 trace 가 켜졌을 때만 자기 통계 배열을 쓴다. trace 없이 `@collect_exec_stats` 만 켜면 워커 여럿이 `tran_stats[tran_index]` 에 원자적이지 않은 `+=` 를 동시에 한다 → `SHOW EXEC STATISTICS` 가 덜 셀 수 있다(전역은 원자적이라 무관). 측정 D 로 확인. |

정적으로 보고 결함이 아닌 것으로 정리한 것:
- PEEK 재시도(`restart_scan_oid`) 때 `read_rows` 를 다시 세는 것은 직렬 `scan_next_heap_scan` 도 11.5 시작 지점부터 같다. 동시 갱신으로 페이지가 바뀐 경우만 해당 — 범위 밖.
- `fetch_time` 은 모든 경로가 `(PSTAT_PB_PAGE_FIX_ACQUIRE_TIME_10USEC 차이)/1000` 로 같은 단위다. 병렬에서 `fetch_time` > `time` 은 워커 합이라 정상(병렬 표기).
- 워커 `on_trace` 는 px_scan·px_query·hash join 태스크가 시작할 때마다 부모 값으로 다시 정한다 — 남는 값 없음.

## 수정 방침 (사용자 지시 2026-10-11, cpp-perf-rules PAR-01·COH-04·COH-12·MEM-03)

범위(Q15, 2026-10-11): C2(`SHOW EXEC STATISTICS` 경합 누락)도 원인이 같아 이번 수정에 포함한다.

워커는 통계를 자기 배열에만 쌓고(thread-local), 끝날 때 한 번 부모(리더의 배열 또는 트랜잭션 통계)에 합친다. 공유 배열에 원자적이지 않은 `+=` 를 동시에 하지 않으며, 합산은 모든 종료 경로(정상 end, close, 오류)에서 한 번만 일어난다. 아무도 통계를 보지 않을 때(감시자 0)는 배열을 만들지 않는다(Q14: 꺼짐 비용 0).

| 결함 | 지금 | 방침 |
|---|---|---|
| D1 | 워커 배열은 있고 `merge_stats` 도 있으나 close 경로가 합산을 건너뛴다(가설) | 합산을 워커 결과를 받는 모든 종료 경로에서 한 번 수행 |
| D2 | 정렬 워커 배열을 합치지 않고 버린다 | 워커 끝에서 리더로 합산; 바깥 줄 page/ioread = 리더 + 워커 합 |
| C2 | 워커 배열은 trace 일 때만; 아니면 `tran_stats` 에 경합 `+=` | 감시 중이면 trace 여부와 무관하게 워커 배열을 쓰고 끝에 합산 |
| (부수) | hash join 워커 통계는 한 블록을 `degree * stats_size` 로 나눠 쓴다 — 조각 경계가 같은 캐시 라인을 공유할 수 있다(MEM-03) | 하지 않음: 경계에 걸리는 값은 통계 배열의 처음·끝 항목으로 자주 바뀌지 않는 값이고, 측정한 근거가 없다 |

### 수정 내용 (엔진 워크트리 `trace-accuracy`, base be683e04c)

공통(`perf_monitor.c/.h`): `perfmon_merge_values` (배열 전체 합산: 카운터·COMPLEX 는 더하고, 타이머는 count·total 을 더하고 max 는 큰 값, PEEK·비율은 건너뜀), `perfmon_add_values_to_local` (스레드가 병렬 워커면 자기 배열에, 아니면 감시 중인 트랜잭션 통계에), `perfmon_parallel_stats_needed` (= trace 이거나 트랜잭션이 감시 중). 7개 오프셋만 옮기던 `perfmon_get_parallel_merged_offsets` 와 그 사용처, 호출처 없던 `perfmon_merge_child_stats_to_parent_stats`, 대체된 `perfmon_merge_parallel_stats_to_tran_stats` 삭제. `perfmon_time_at_offset`·`perfmon_time_bulk_at_offset` 도 병렬 워커면 자기 배열에 쓴다(전에는 트랜잭션 통계에 경합 쓰기).

| 결함 | 수정 |
|---|---|
| C1 | `qualified_rows++` 를 데이터 필터 통과 뒤로 |
| D1 | px_scan 워커는 끝날 때(`task::finalize`) 배열 전체를 `trace_handler::add_px_stats` 로 넘기고, 리더는 `trace_handler::merge_stats` 에서 한 번 합친다(`m_merged` 로 end·close 중복 방지). `scan_close_parallel_{heap,list,index}_scan` 모든 결과 유형에서 `wait_for_workers` + `merge_stats`. 워커의 SCAN 줄 fetch 는 페이지·슬롯 읽기 구간만 따로 잰다(`m_scan_fixes`, 직렬 `scan_next_scan_local` 과 같은 범위). 리더 스레드에 쓰지 않는 배열을 만들던 `manager::open` 코드 삭제 |
| D2 | 정렬 워커 3곳(`sort_listfile_execute`, `sort_merge_nruns_queue_cb`, `sort_put_result_for_parallel`)이 배열을 자기 `SORT_PARAM::px_stats` 로 넘기고(소유권 이전, 병합 큐 슬롯 재사용 시 더함), `sort_listfile` 가 워커를 모두 정리한 뒤 한 번 합친다 |
| D3 | `qexec_orderby_distinct` 기준값을 trace 이면 항상 읽음 |
| D4 | `qexec_hash_gby_put_next` 가 같은 키를 합칠 때 `tuple_count` 도 더함. 범위가 처음 본 것보다 넓다: 병렬 hash 집계는 워커마다 partial 항목을 남겨 GROUPBY readrows 가 거의 항상 워커 하나 몫이었다(Q1 14,829,611 / 59,142,609, Q4·Q9·Q12·Q13·Q21·Q22 도). 직렬 `hash: true` 도 밀려난 그룹이 있으면 모자랐다(Q10 1,001,406 / 입력 1,147,084, Q18 59,972,323 / 59,986,052). 수정 후 병렬 값은 입력 SCAN readrows 와 같다. `input_recs` 는 MERGE 원본 중복 검사(`ER_MERGE_TOO_MANY_SOURCE_ROWS`)에도 쓰인다 |
| D5 | JSON 덤프 조건을 text 와 같게(`S_PARALLEL_HEAP_SCAN \|\| S_HEAP_SCAN`) |
| C2 | px_scan·px_query·hash join·정렬 워커가 trace 가 아니어도 감시 중이면 자기 배열을 쓰고 끝에 넘긴다 |

수정하며 찾은 것(같은 원인, 같이 고침):
- E1 px_query: 루트 스레드는 executor 를 만들 때부터 `run_jobs` 끝까지 자기 배열에 쌓는데, 끝에 7개 오프셋만 트랜잭션 통계로 옮겼다 → 그 사이 리더가 센 정렬 page·lock 등은 세션 통계에서 사라졌다. 이제 배열 전체를 옮긴다. `run_jobs` 전에 오류로 끝나면 `~query_executor` 가 같은 정리를 한다(전에는 배열이 남아 그 스레드의 다음 문장 통계가 사라짐).
- E2 px_query: 작업이 끝나면 `on_trace` 를 원래 값이 아니라 `!!trace_context_p` 로 되돌렸다.
- E3 정렬 워커는 trace 일 때만 `sort_stats_active` 를 켜서 trace 없이 도는 병렬 정렬의 정렬 page 가 statdump(`Num_sort_data_pages`·`Num_sort_io_pages`)에서 빠졌다. 리더(`sort_listfile`)처럼 항상 켠다.
- E4 `qexec_init_next_partition` 이 파티션을 바꿀 때 리더 스레드의 `m_px_stats`(그 스캔과 무관한 배열, hash join 이 쓰던 것일 수도 있음)를 스캔 fetch 에 더했다. 삭제.
- E5 px_scan `manager::open` 이 리더 스레드의 `m_px_stats` 를 memset 하고 `merge_stats` 가 해제해서, 같은 스레드에서 hash join 이 모아 두던 값을 지울 수 있었다. 그 코드 삭제(D1 항목).

범위 밖(옛 동작 유지): `btree_sort.c` (인덱스 생성), `heap_file.c` 병렬 용량 조사, 히스토그램 샘플러 — trace 일 때만 배열을 쓰고 넘기지 않는다.

## 측정 하네스

`.git_ignored_dir/scratch/trace115/harness/run_case.sh` — 단계마다 별도 csql 세션:
A 예열(컴파일·계획) → statdump G0 → B(text trace) → G1 → E(`@collect_exec_stats` + trace, 질의 바로 뒤 `SHOW EXEC STATISTICS ALL`) → [full] G2 → D(통계만, trace 없음) → G3 → C(JSON trace).
`SHOW EXEC STATISTICS` 는 마지막 감시 시작 이후의 트랜잭션 통계를 읽고 지운다. `SHOW TRACE`·`SHOW EXEC STATISTICS` 는 `DONT_COLLECT_EXEC_STATS` 문장이라 감시를 멈췄다가 다시 시작하며(이때 `tran_stats` 를 0 으로 지움) 그래서 통계 문장은 질의 바로 뒤에 둔다.

## 실측

### pilot (2026-10-11, 기본 변형, 6 케이스)

| 케이스 | base trace / 전역 | cur trace / 전역 | 페이지 수 기준점 |
|---|---|---|---|
| a02 orders 직렬 heap 스캔 | 243717 / 243725 | 160105 / 160113 | heap 페이지 base 243717, cur 160104 |
| a03 pk_orders 커버링 스캔 | 80861 / 80869 | 15563 / 15571 | 인덱스 페이지 base 15564(leaf 15545), cur 15579 |
| q06 lineitem (cur 병렬 4) | 1231321 / 1231331 | 716391 / 716401 | heap 페이지 base 1231321, cur 716382 |
| s15 파티션 풀 스캔 (cur 병렬) | 123127 / 123135 | 71656 / 71668 | — |

- 전역 − trace 는 두 빌드 모두 +8~+12 로 일정하다(질의 밖 몫). 직렬 heap 스캔 fetch = heap 페이지 수(base 정확히, cur +1).
- base 의 커버링 인덱스 스캔은 leaf 페이지의 약 5배를 fix 한다 — 옛 btree 범위 스캔이 OID 묶음마다 leaf 를 다시 잡는 방식. 빌드 간 차이(정당).

### 전체 행렬 (2026-10-11, 46 케이스 × 4 변형, 전부 ok)

요약 CSV: `runs/matrix/{cur/cur-def.csv, base.csv, serial.csv, oldplan.csv}`. ①③④ 는 DB 사본 12개(data_buffer 2G)에서 병렬로 쟀다.

- 같은 실행(B)의 전역 − trace: ① base, ③ cur 직렬, ④ cur 옛 계획 모두 거의 +2~+23(질의 밖 몫). 예외 q16 +100~212, base s18 +132 — 11.5 시작 지점부터 같은 크기, 범위 밖.
- 세션(E) − trace 의 수천~수만 차이는 서로 다른 실행(B·E)의 차이다(2G 버퍼에서 정렬·temp 가 실행마다 다름). base 에도 같은 크기로 나온다 → 판정에 쓰지 않는다.
- ⇒ 직렬 경로의 trace 총계는 두 빌드 모두 정확하다. 총계 불일치는 모두 병렬 경로(② 의 C1·D1·D2·C2)에서 나온다. D3·D4 는 직렬에서도 나는 항목별 결함.
- text 와 JSON 의 구조: 직렬은 일치(PARTITION·CTE 는 표현 차이), 병렬 파티션만 D5.
- C2 실측(② 의 D 단계, trace 끔): 세션 통계가 전역보다 q03 −3.5%, q05 −2.5%, q13 −7.3%, s21 −4.0% 적다. 직렬 ③ 은 차이 0.

미확정 소항목: 현재 빌드 직렬 heap 스캔이 heap 페이지 수보다 fix 를 1번 더 한다(a02 160105 vs 160104). 그 fix 는 trace·statdump 둘 다 세므로 trace 결함 아님.

### 수정 후 재측정 (2026-10-11, trace-accuracy 워크트리, base be683e04c, 기본 변형 ②, DB 사본 8개 병렬)

요약 CSV: `runs/fix/{rel.csv, odbg.csv}`.

| 빌드 | 케이스 | 전역 − trace (같은 실행 B) | 전역 − 세션 (trace 없음, D) | core·assert |
|---|---|---|---|---|
| 수정 전 cur release ② | 46 | 중앙값 20, 최대 34,392,886 (q03) | 최대 5,976,189 (q13) | — |
| 수정 release | 46/46 ok | 중앙값 4, 최대 23 (q16 만 100) | 0 (DML s17 306, s18 865 — vacuum 몫, 직렬 ③ 과 같은 크기) | — |
| 수정 optdebug | 46/46 ok | 8~92 (q16 400) | 0 (DML 제외) | 없음 |

- 병렬 trace 합계가 직렬 ③(최대 108, q16)과 같은 정확도가 됐다. q16 은 직렬에서도 나는 별개 항목.
- 항목별: q03 바깥 SCAN `readrows: 15000000`, q06 SCAN `rows: 1139264`, s08 GROUPBY page 리더+워커, ORDERBY page 자기 정렬만, 병렬 GROUPBY readrows = 입력 SCAN readrows(q01 59,142,609, q10 1,147,084), s15 JSON `"parallel heap"` 있음.
- optdebug 의 fetch 절대값은 release 의 약 4배(직렬 a02 도 640,420 vs 160,105) — debug 빌드의 page fix, 수정과 무관.
- CTP(optdebug): sql 17510/17510, medium 975/975. shell TC cbrd_27599 13개 검사: 수정 빌드 13/13(2회), develop be683e04c release·optdebug 8개 NOK.
