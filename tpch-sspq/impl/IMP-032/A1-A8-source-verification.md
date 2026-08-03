# IMP-032 G002 — 착수 전 소스검증 A1–A8 (spec §A)

- 검증 대상 스택: worktree `/home/cubrid/dev/tpch-sspq-impl-r1/worktrees/IMP-032` @ `61f4b4cf967dbc2f0cd18422b83561ef44366382` (IMP-015 patch commit), 캠페인 동결 base `607f1ee9fb2394de129e083602c84a6525fc685c`
- 시점: **첫 소스 수정 전** (worktree clean; `M cubrid-cci`는 submodule 체크아웃 부수효과이며 §6-a-1이 명시한 benign dirt)
- 규범: IMPL-SSOT `276d8e866f0f4702648ccb9b8c00c8c5410931e9` / blob `15b42ddca521444fa54b34b0fa8477ed2df643f6`; spec blob `580cd4f5f17ab47b3418352d1aed18689aa9e258`
- 인용 `file:line`은 모두 위 worktree에서 직접 판독한 것이다.

## 판정 요약

| # | 가정 | 기대 답 | **판정** |
|---|---|---|---|
| A1 | run 임시파일 페이지 경계 = 튜플 경계 | holds | **holds** |
| A2 | `sort_put_result_from_tmpfile`가 임의 `start_index` 시작 + 조건부 정지를 지역 수정으로 수용 | holds | **holds** (필드 1개 추가 필요) |
| A3 | `GROUPBY_STATE` 워커별 복제 가능 (리더 전역 은닉 상태 없음, 또는 열거·복제 가능) | holds | **반증 — stop-and-report** |
| A4 | 직렬 폴백 게이트 조건이 게이트 시점에 판별 가능 | enumerable | **holds (5개 조건 전수 열거)** |
| A5 | qfile 연결 coda가 group-by 출력에서도 순서 보존 | holds | **holds** |
| A6 | `GROUPBY_STATS`에 finalize 국면 px 통계 확장 수용 | holds | **holds** (XASL 직렬화 무접촉 확인) |
| A7 | 워커 스레드 문맥에서 집계·finalize 호출 안전 | holds | **조건부 holds** (A4 게이트 전제 하에서만) |
| A8 | phase ① 예약 워커를 ③ drain에 재사용 | holds | **holds** |

spec §A 규정: **A3 반증 시 stop-and-report — 복제 불가능한 상태가 있으면 스코프 재설계(부분 직렬화) 여부를 사용자가 결정.** 따라서 G002 이후 첫 소스 수정으로 진행하지 않는다.

---

## A1 — 페이지 경계 = 튜플 경계 (holds)

`sort_put_result_from_tmpfile` (`src/storage/external_sort.c:3294-3384`):

- `sort_read_area (…, &sort_param->temp[result_file_idx], current_pages, read_pages, sort_param->internal_memory)` (3313-3315) 로 페이지 단위로 읽는다.
- 각 페이지에서 `slot_num = sort_spage_get_numrecs (cur_pgptr)` (3326) → `sort_spage_get_record (cur_pgptr, i, &record, PEEK)` (3330) 로 **페이지 자신의 slot table**을 통해 레코드를 꺼낸다. 페이지를 걸치는 레코드는 이 구조상 표현 불가.
- 페이지에 안 들어가는 long record는 `record.type == REC_BIGONE` 판정 후 `sort_retrieve_longrec` (3338-3346) 로 overflow에서 복원 — drain에서 이미 처리된다.
- 페이지 전진은 `cur_pgptr += DB_PAGESIZE; cur_read_pages--; current_pages++;` (3370-3373).

⇒ `sort_split_last_run`의 페이지 단위 분할(3394-3421)을 **무수정으로** 쓸 수 있다는 전제가 성립.

## A2 — 임의 `start_index` 시작 + 조건부 정지 (holds, 단 전체 페이지 수 필드 필요)

- 시그니처가 이미 `sort_put_result_from_tmpfile (THREAD_ENTRY *, SORT_PARAM *, int start_pagenum)` (3295) 이고 `current_pages = start_pagenum` (3298) 으로 시작한다.
- ORDER_BY 병렬 drain이 이미 이 인자를 사용: `sort_put_result_for_parallel`에서 `sort_put_result_from_tmpfile (thread_p, sort_param, sort_param->file_contents[0].start_index)` (5305). 직렬 경로는 `sort_run_final_single`에서 `…, 0)` (5682).
- 종료 조건은 `tot_pages = sort_param->file_contents[result_file_idx].num_pages[0]` (3308) 기반의 이중 루프 — 워커별 `num_pages[0]`은 `sort_split_last_run`이 자기 몫으로 설정(3410).
- **경계 skip/overrun 수용성**: 선두 skip은 루프 내부의 튜플별 분기로 지역 수정 가능. 말미 overrun은 자기 몫을 넘어 계속 읽어야 하므로 **consolidated run의 전체 페이지 수**가 워커에 필요하다 — 현재 워커 `px_sort_param[i]`는 자기 몫만 알고, 전체 값은 리더 `sort_param->file_contents[result_file_idx].num_pages[0]` (3401-3402) 에만 있다. `SORT_PARAM`에 필드 1개(예: `px_total_result_pages`)를 `sort_split_last_run`에서 채워 넣는 방식으로 해결 가능(ORDER_BY 경로 불변).

## A3 — `GROUPBY_STATE` 워커별 복제 (**반증**)

### A3-1. 복제 가능한 부분

| 항목 | 근거 | 판정 |
|---|---|---|
| 집계 누산기 `g_dim[N].d_agg_list` | `qexec_gby_init_group_dim` (`src/query/query_executor.c:20258-20283`) 이 이미 차원별로 `AGGREGATE_TYPE`를 memcpy + `accumulator.value`/`value2`를 `db_value_copy`로 **복제**한다. 해제는 `qexec_gby_clear_group_dim` (20299-20332) | 기존 기계장치로 복제 가능 |
| 출력 리스트 `output_file` | ORDER_BY 선례: 워커 0은 origin 재사용, 1..n-1은 `qfile_open_list (…, type_list, sort_list, query_id, flag \| QFILE_NOT_USE_MEMBUF, NULL)` (`external_sort.c:5291-5301`) | 복제 가능 |
| 작업 버퍼 `current_key` / `gby_rec` / `input_tpl` / `output_tplrec` | `groupby_state` 구조체 (`query_executor.c:242-245`); 워커별 사적 버퍼로 할당 가능 | 복제 가능 |
| 입력 스캔 `input_scan` | GROUP_BY 병렬 경로는 워커별 `SORT_INFO` + `qfile_clone_list_id` + `sort_px_list_state` 를 이미 만든다 (`external_sort.c:5558-5600`) | 복제 가능 |

### A3-2. 복제 **불가능**한 리더 전역 은닉 상태 (전수 열거)

1. **공유 `g_val_list` / `g_regu_list` 인스턴스 상태** — A3가 반증 예시로 명시한 항목 그 자체.
   `qexec_gby_agg_tuple` (`query_executor.c:4576-4602`) 은 튜플마다
   `fetch_val_list (thread_p, gbstate->g_regu_list, &gbstate->xasl_state->vd, NULL, NULL, tpl, peek)` (4587)
   로 **XASL 소유 `g_val_list`의 DB_VALUE에 값을 써 넣고**, 직후
   `qdata_evaluate_aggregate_list (…, g_dim[i].d_agg_list, &gbstate->xasl_state->vd, …)` (4597) 가 같은 DB_VALUE를 operand로 읽는다.
   `g_regu_list`/`g_val_list`는 `buildlist->g_regu_list`/`g_val_list` (5403-5404) — XASL 트리 소유. 워커 둘이 동시에 수행하면 같은 DB_VALUE에 동시 기록 ⇒ data race + 오답.
2. **`g_output_agg_list` (XASL `buildlist->g_agg_list`)** — `qexec_gby_finalize_group` (`19936-19960`) 이
   `pr_clear_value (g_outp->accumulator.value); *g_outp->accumulator.value = *d_aggp->accumulator.value;` (19947-19948)
   로 XASL 소유 DB_VALUE에 결과를 옮긴다. 이 DB_VALUE가 outptr/having regu 트리의 **바인딩 지점**이라 사적 복제로 대체할 수 없다(복제하면 regu 트리가 여전히 원본을 가리킨다).
3. **`having_pred` + `g_outptr_list` + 공유 `xasl_state->vd`** — `eval_pred (thread_p, gbstate->having_pred, &xasl_state->vd, NULL)` (19973), `qexec_generate_tuple_descriptor (…, gbstate->g_outptr_list, &xasl_state->vd)` (20047-20048), `qdata_copy_valptr_list_to_tuple (…, gbstate->g_outptr_list, &xasl_state->vd, …)` (20081). 전부 공유 regu 트리와 공유 `VAL_DESCR`에서 평가되며, regu 평가는 노드별 scratch DB_VALUE에 기록한다.
4. **`agg_hash_context` 부분리스트 커서** — `qexec_gby_put_next` 는 그룹 경계마다
   `if (info->hash_eligible && info->agg_hash_context->part_scan_code == S_SUCCESS)` 분기에서
   `curr_part_value` / `temp_key` / `part_scan_id` 를 소비한다 (5191-5228, 5250-5309). 커서는 `qexec_groupby` 에서 정렬된 부분리스트를 열고 첫 키를 로드해 놓은 **단일 순차 커서**(5626-5638)이며, 그룹 순서와 lock-step으로만 의미가 있다. XASL을 복제해도 복제본의 `agg_hash_context`는 **빈 것**이라 리더의 spill 산출물을 대신하지 못한다.
   ※ 이 분기는 IMP-032의 표적 상황에서 **살아 있을 수 있다**: `gby_px.hash_eligible = (gbstate.hash_eligible && agg_hash_context->state != HS_REJECT_ALL)` (5682) 이므로 HS_REJECT_ALL이면 병렬이 켜지지만, `gbstate.hash_eligible` 자체는 여전히 1이고 이전에 축출(spill)이 있었다면 `part_scan_code == S_SUCCESS`다. 실제 Q15/Q18에서 축출이 있었는지는 D1 프로브에서 확인해야 한다(해시 **포기**만 있고 **축출**이 없으면 `part_list_id`가 비어 `S_END`(5643)이므로 이 항목은 무해한 보수적 게이트가 된다).
5. **단발 발화·전역 카운터**: `grbynum_val` + `grbynum_flag` + `SORT_PUT_STOP` (19987-20019) — GROUPBY_NUM/LIMIT의 전역 카운터이며 STOP은 전역 경계에서 정확히 한 번만 발화해야 한다. `gbstate->xasl->groupby_stats.rows++` (20101) 는 비원자적 공유 카운터. `composite_lock`/`upd_del_class_cnt` (5662-5673, 20028-20042) 는 전역 락 상태.

### A3-3. 왜 "ORDER_BY 분기 미러링"으로는 해결되지 않는가

- ORDER_BY의 병렬 drain put_fn `qexec_ordby_put_next` (`query_executor.c:3772-3900`) 는 **순수 튜플 복사**다: 페이지에서 튜플을 집어 `qfile_add_tuple_to_list (…, info->output_file, data)` (3878) 로 옮기고, 선택적으로 ORDERBY_NUM 값만 덮어쓴다. XASL 표현식 평가·집계·HAVING·출력튜플 생성이 **없다**.
- 더 결정적으로, put_fn이 공유 상태를 가지면 병렬화하지 않는다는 결정이 **이미 소스에 명시**돼 있다. `sort_end_parallelism`의 ORDER_WITH_LIMIT 분기 (`external_sort.c:5718-5745`):
  > `/* ORDER_WITH_LIMIT: fan-in only, then serial put via put_fn (qexec_ordby_put_next). put_fn must not run in parallel because ordbynum_val state is shared and SORT_PUT_STOP must fire exactly once at the global LIMIT boundary. */`
  즉 `ordbynum_val` **하나** 때문에 ORDER BY 계열도 직렬 drain으로 내려간다. GROUP_BY의 put_fn은 그보다 훨씬 큰 공유 상태(위 1~5)를 갖는다.
- `put_fn = (ordbynum_val) ? &qexec_ordby_put_next : NULL;` (`query_executor.c:4258`) — 평범한 ORDER BY의 병렬 drain은 put_fn이 아예 NULL이다.

### A3-4. 복제 기계장치는 존재하지만 spec 반경 밖이다

병렬 heap/list/index scan은 정확히 이 문제를 **워커별 XASL 완전 복제**로 해결한다
(`src/query/parallel/px_scan/px_scan_task.cpp:569-643`):

- `m_uses_xasl_clone`이면 `xcache_find_xasl_id_for_execute (…, &m_xasl_cache_entry, &m_xasl_clone)` + `xasl_find_by_id` (579-585); 아니면 `stx_map_stream_to_xasl (…, main_thread_p->xasl_unpack_info_ptr->packed_xasl, packed_size, &m_xasl_unpack_info)` 로 packed XASL을 **워커마다 재해석** (597-604). 둘 다 `main_thread_p->m_px_lock_mutex` 보호.
- 워커별 `xasl_state` 할당 + `VAL_DESCR` memcpy + `dbval_ptr`을 `pr_clone_value`로 복제 (616-641).
- 정리: `qexec_clear_xasl` + `xcache_retire_clone`/`xcache_unfix` 또는 `free_xasl_unpack_info` (502-518).
- 워커 문맥에서 `eval_pred (…, m_xasl->if_pred, m_vd, NULL)` (691) 등을 자기 복제본으로 평가한다.

이 경로를 IMP-032에 도입하는 것은:

- **§5-d 하드스톱 저촉** — `stx_map_stream_to_xasl` / `xcache_*` 는 **XASL 직렬화 및 XASL 캐시 서브시스템**이며, spec이 선언한 수정 반경(`external_sort.c`, `query_executor.c`, 헤더 소폭)의 밖이다. IMPL-SSOT §5-d는 "unanticipated subsystem" 및 "XASL serialization" 접촉을 stop-and-report로 규정한다.
- **LOC 밴드 붕괴** — spec 밴드 low 50 / likely 140 / high 280, 하드스톱 420. px_scan의 대응 기계장치는 수천 줄 규모이고, 최소 이식(워커별 XASL 복제 + 복제본 기준 gbstate 구성/해제 + 경계 skip/overrun + coda + 5개 폴백 게이트 + 통계 합산)도 420을 넘길 것으로 판단한다.
- 그리고 A3-2의 4번(부분리스트 커서)은 복제로도 해결되지 않아 별도 직렬 게이트가 여전히 필요하다.

⇒ **A3 반증 확정**: 리더 전역 은닉 상태가 존재하며, 열거는 가능하나 **spec이 정한 스코프 안에서는 복제 불가능**하다.

## A4 — 직렬 폴백 게이트 조건 (holds, enumerable)

`qexec_groupby`가 `sort_listfile (…, SORT_GROUP_BY, &gby_px)` (5686-5688) 를 호출하기 **전에** 판별 가능한 조건 전수:

| # | 조건 | 판별식 (판별 시점 근거) | 왜 필요한가 |
|---|---|---|---|
| ① | ROLLUP / Data Cube | `buildlist->g_with_rollup` (5405) → `gbstate.g_dim_levels > 1` (`20225-20229`) | 그룹 경계를 가로지르는 super-group 누산 (`qexec_gby_finalize_group_dim` 19815-19879) |
| ② | HAVING 서브쿼리 | `buildlist->eptr_list != NULL` (5403) | finalize가 워커 문맥에서 `qexec_execute_mainblock` 호출 (19925-19933) — 리더 전용 전제 |
| ③ | GROUPBY_NUM / LIMIT | `buildlist->g_grbynum_val != NULL` (5402) | 전역 카운터 + `SORT_PUT_STOP` 단발 발화 (19987-20019) |
| ④ | MULTI_UPDATE_AGG (composite lock) | `XASL_IS_FLAGED (xasl, XASL_MULTI_UPDATE_AGG)` (5662) | 전역 락 누적 (20028-20042) |
| ⑤ | 해시 부분리스트 병합 활성 | `gbstate.agg_hash_context->part_scan_code == S_SUCCESS` — 값이 `sort_listfile` 직전(5633-5638) 또는 `S_END`(5643)로 확정됨 | 단일 순차 커서, 복제 불가 (A3-2 4번) |

전달 경로: `SORT_LISTFILE_PX_ARG` (현재 `key_info`/`input_list`/`hash_eligible`/`stats`/`parallelism`) 에 필드를 추가하고 `sort_check_parallelism`의 SORT_GROUP_BY 분기 (`external_sort.c:5228-5247`, 현재 `px->hash_eligible`만 검사) 에서 게이트한다. 게이트 시 기존 직렬 경로(`sort_run_final_single`, 5851)를 그대로 타므로 회귀 반경은 0.

⇒ **enumerable holds**. (단 ⑤가 Q15/Q18에서 상시 활성이면 표적 질의가 게이트에 걸려 효과가 0이 되므로, D1 프로브에서 반드시 확인해야 한다.)

## A5 — qfile 연결 coda (holds)

ORDER_BY coda (`external_sort.c:4907-4947`):

- 워커 0의 출력을 origin으로 삼고(4908), 워커 1..n-1을 **순서대로** 연결: 빈 리스트는 skip (4915-4919), `temp_file_type == FILE_QUERY_AREA` 면 `qfile_append_list` (4924) — 그 외에는 `qfile_connect_list` (4934).
- 마지막에 `qfile_reopen_list_as_append_mode (thread_p, origin_list_id)` (4943).
- 정리 경로도 존재 (4952-4961).

모두 `QFILE_LIST_ID` 수준 연산이며 group-by 출력 리스트도 동일한 `QFILE_LIST_ID`다(`qfile_open_list (…, buildlist->after_groupby_list, …, ls_flag, NULL)` — `query_executor.c:5435-5436`). `ls_flag`에 `QFILE_FLAG_RESULT_FILE`이 붙는 경우(5429-5433)도 coda의 `FILE_QUERY_AREA` 분기가 이미 커버한다.

⇒ holds. 순서 보존은 "워커 i의 구간이 키 순서대로 뒤따른다"는 분할 성질에서 나오고, coda는 그 순서대로 연결한다.

## A6 — `GROUPBY_STATS` finalize 국면 px 통계 확장 (holds)

- `struct groupby_stat` = `src/query/xasl.h:987-1003`: `groupby_time`, `groupby_pages`, `groupby_ioreads`, `rows`, `groupby_hash`, `run_groupby`, `groupby_sort`, `parallel_num`, `px_min/max_groupby_{time,pages,ioreads}`.
- 현재 채우는 곳: `sort_end_parallelism` GROUP_BY 분기 (`external_sort.c:5803-5812`) — phase ① 워커 시간만.
- **XASL 직렬화 무접촉 확인**: `stream_to_xasl.c:2383` 에서 `memset (&xasl->groupby_stats, 0, sizeof (xasl->groupby_stats));` 뿐이고 `xasl_to_stream.c`에 pack 코드가 없다 ⇒ 런타임 전용 필드. 필드 추가는 §5-d의 "XASL serialization" 접촉이 **아니다**.
- 트레이스 방출: `query_dump.c:3376-3377` (JSON `"min time"`/`"max time"`), `:3973` (text `", time: %lu..%lu"`). 발동증명 신호(D6 2층)는 여기에 finalize 국면 항목을 추가하면 되고, base(IMP-015 단독) 바이너리에는 해당 키가 없으므로 부재 확인도 성립.

⇒ holds (수정 파일에 `query_dump.c` 소폭 추가).

## A7 — 워커 스레드 문맥 안전성 (조건부 holds)

성립하는 부분 (`sort_put_result_for_parallel` preamble, `external_sort.c:5265-5285`):

- `thread_ref.tran_index = sort_param->px_orig_thread_p->tran_index;` (5273), `m_px_orig_thread_entry` (5274), `conn_entry` (5275) 승계.
- `thread_p->push_resource_tracks ()` (5277) / `pop_resource_tracks ()` (5336).
- 트레이스 시 `perfmon_initialize_parallel_stats` / `destroy` (5283, 5334).
- 에러 전파: 실패 시 `sort_param->main_error_context->get_current_error_level ().swap (cuberr::context::get_thread_local_error ());` (5343) — 단 **실패 워커 1개의 컨텍스트만** 전달된다(다중 실패 시 마지막 승자).

성립하지 않는 부분:

- `qexec_gby_finalize_group` → `qexec_execute_mainblock (thread_p, xptr, xasl_state, NULL)` (19927): HAVING 서브쿼리 XASL 실행. px_scan은 이 계열을 **복제된 XASL + 워커별 vd** 위에서만 하고, 복제/언팩 구간을 `main_thread_p->m_px_lock_mutex`로 보호한다(`px_scan_task.cpp:578-611`). 정렬 워커 문맥에서 리더 XASL로 직접 호출하는 것은 안전하지 않다.
- `qexec_add_composite_lock` (20034): 전역 락 누적.
- `SORT_PUT_STOP` 단발 발화 요구(19987-20019) — ORDER_WITH_LIMIT이 직렬을 택한 바로 그 이유(5720-5722).

⇒ **조건부 holds**: A4의 ②③④ 게이트로 위 호출들을 배제하면 스레드/트랜잭션/에러 문맥 자체는 성립한다. 그러나 A3-2의 1~3번(공유 val_list/regu/output agg)은 게이트로 배제할 수 없는 **상시** 경로이므로, A7의 성립은 A3 해결에 종속된다.

## A8 — phase ① 예약 워커의 ③ 재사용 (holds)

- `SORT_EXECUTE_PARALLEL` (`src/query/parallel/px_sort.h:41-49`) 은 `sort_param->px_worker_manager->push_task(task)` 로 태스크를 밀어넣고, `SORT_WAIT_PARALLEL` (52-78) 이 `px_status` 폴링 후 `wait_workers ()` 한다.
- 그 매니저는 `sort_check_parallelism`의 SORT_GROUP_BY 분기에서 예약된 것 (`external_sort.c:5244-5246`, `try_reserve_workers` + `get_reserved_workers`로 부분 예약 클램프).
- ORDER_BY는 이미 같은 매니저를 phase ③ 병렬 drain에 재사용한다: `sort_merge_run_for_parallel` 내부의 `SORT_EXECUTE_PARALLEL (parallel_num, px_sort_param, sort_put_result_for_parallel)` (4900) — 이 함수는 `sort_end_parallelism` (5712) 에서 호출되며 그 시점에 워커는 아직 예약 상태다.
- GROUP_BY도 동일한 `sort_end_parallelism` (5783-5856) 안에서 ③를 수행하므로 추가 예약이 필요 없다.

⇒ holds.

---

## 결론과 후속 (spec §A 규정 집행)

- A1/A2/A4/A5/A6/A8 holds, A7 조건부 holds, **A3 반증**.
- spec §A: "A3 반증 시 **stop-and-report** — 복제 불가능한 상태가 있으면 스코프 재설계(부분 직렬화) 여부를 사용자가 결정". IMPL-SSOT §5-d(unanticipated subsystem / XASL serialization)와 §11-a(materially different implementation options)도 동시에 저촉된다.
- 따라서 **첫 소스 수정으로 진행하지 않는다.** `implementation-plan.md`(§5-c)는 스코프가 확정된 뒤에 작성해야 의미가 있으므로 보류한다.
- 사용자 결정 선택지:
  - **(A) 스코프 재설계 승인** — px_scan식 워커별 XASL 복제 도입. spec 개정 + LOC 밴드 재산정(추정 600–1200) + XASL 직렬화/캐시 접촉 승인 필요.
  - **(B) 카드 요소 1로 피벗** — ② 계층형 fan-in merge 병렬화. `sort_merge_queue_run` 계열은 키 비교와 페이지 I/O뿐이고 XASL 상태를 만지지 않아 A3 문제가 원천적으로 없다. spec D4가 "프로브가 ② 지배를 보이면 별도 결정으로 재소환"이라고 이미 문을 열어 두었다 → **D1 프로브의 ②/③ 귀속이 판정 근거**.
  - **(C) 부분 직렬화** — ③ drain의 비-XASL 부분(페이지 읽기/레코드 디코드/long record 복원)만 선행 프리페치로 겹치기. 이득 상한이 낮다.
  - **(D) IMP-032 연기/기각.**
- **다음 자율 행동**: 사용자 결정을 기다리는 동안 D1 귀속 프로브(spec D1, handoff 4번)를 수행한다. 프로브는 보존 `install/IMP-015` 바이너리에 대한 **읽기 전용 측정**이고 소스 수정이 아니며, ②/③ 귀속은 선택지 (A)/(B) 판정의 유일한 정량 근거다. 프로브가 `UNPROVABLE_ON_THIS_HOST`를 내면 그 자체로 별도 정지 조건이므로 사용자 기상 전에 알려 두는 것이 낫다.

## §8-c 상태 블록

```yaml
TPCH_SSPQ_IMPL_STATUS:
  campaign_id: tpch-sspq-impl-r1-20260803
  imp_id: IMP-032
  impl_ssot_commit: 276d8e866f0f4702648ccb9b8c00c8c5410931e9
  impl_ssot_blob_sha: 15b42ddca521444fa54b34b0fa8477ed2df643f6
  session_id: 019fc85d-8da5-7000-bc9e-7f97de474072
  stage: G002-A1-A8-verification-complete (A3 REFUTED)
  state: working
  branch: impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize
  report_commit: null
  verdict: null
  artifact_fingerprint: null
  timestamp: 2026-08-04T01:45:00+09:00
  next_action: D1 귀속 프로브(②/③ 귀속) 수행 → 선택지 A~D 사용자 결정 대기 (첫 소스 수정 금지)
  source_modified: none (worktrees/IMP-032 clean at 61f4b4cf9)
```
