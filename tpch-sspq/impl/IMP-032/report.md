# IMP-032 report (구 IC-5) — GROUP BY 리더 merge/finalize 병렬화: **stopped**

> **verdict `stopped`** — `A3-refuted; UNPROVABLE_ON_THIS_HOST on Q15`.
> 구현에 **착수하기 전** 정지했으므로 `accepted`도 `rejected`도 아니다. §7의 accept/reject 판정은
> 처치(P 바이너리)에 대한 측정을 전제하는데, 이 IMP는 소스를 한 줄도 바꾸지 않았고 A/B를 한 블록도
> 돌리지 않았다. 정지는 확정 스펙이 규정한 두 개의 stop-and-report 조건이 실제로 발동한 결과다.
>
> **IMP-015는 별개다** — 구현 완료·accepted(provisional)로 그대로 서 있다. §16 참조.

## 1. Identity, pins and diff

| 항목 | 값 |
|---|---|
| IMP ID | `IMP-032` — 구 개선 후보 레지스트리 `IC-5`(⑤). 스펙 D3에 따라 편입, 이후 next_id는 `IMP-033` |
| lane | performance |
| 캠페인 | `tpch-sspq-impl-r1-20260803` |
| IMPL-SSOT | commit `276d8e866f0f4702648ccb9b8c00c8c5410931e9` / blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` (§1-d 7단계 전수 통과, 드리프트 없음) |
| 확정 스펙 | `tpch-sspq/impl/IC-5-implementation-spec.md` / blob `580cd4f5f17ab47b3418352d1aed18689aa9e258` |
| CUBRID base SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (캠페인 전체 동결) |
| branch | `impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize` |
| branch base | `61f4b4cf967dbc2f0cd18422b83561ef44366382` (IMP-015 patch commit — 스펙 D2 스태킹, 사용자 승인) |
| patch commit | **없음** |
| **소스 수정** | **0 파일 / 0 라인.** `git -C worktrees/IMP-032 status --porcelain` = 빈 출력(`cubrid-cci` submodule 마커는 §6-a-1이 명시한 benign build dirt), `rev-parse HEAD` = `61f4b4cf9…`, `rev-list --count 61f4b4cf9..HEAD` = **0** |
| diffstat | 없음 |
| worktree | `/home/cubrid/dev/tpch-sspq-impl-r1/worktrees/IMP-032` — clean 상태로 보존 |

§6-a-1 빌드 사전검증 선행 항목도 전수 일치했다(빌드는 수행하지 않았다): `cubrid-cci` @ `2fb8d6d0…`
초기화, `cubrid-jdbc`/`cubridmanager` 미초기화, `CMakePresets.json` sha256 `1818a143…`,
`CMakeUserPresets.json` 부재, GCC 8.5.0 / ld 2.30-123.el8 / cmake 3.26.5 / ninja 1.8.2.

## 2. Actual changed LOC and files

| 항목 | 값 |
|---|---|
| 계획 밴드 (스펙 §B 항목 4) | low 50 / likely 140 / high 280 |
| §5-d 하드스톱 | 420 (= high × 150%) |
| **실제** | **0 파일 / 0 라인** — 150% 검사 해당 없음 |

§5-d는 **다른 축에서 발동했다**. A3 반증(§4)을 해소하려면 병렬 scan의 워커별 XASL 복제 기계장치를
들여와야 하고, 그것은 **XASL 직렬화 / XASL 캐시 서브시스템 접촉**이다(줄 수와 무관한 독립 정지 조건).
그 경로로 재산정한 LOC:

| 재산정 항목 | LOC |
|---|---|
| 워커별 XASL 복제 + 워커별 `xasl_state`/`VAL_DESCR` + 해제 | 120–160 |
| 복제본 BUILDLIST 노드 기준 워커별 `GROUPBY_STATE` 구성/해제 + 출력 리스트 | 80–140 |
| drain 그룹 경계 skip/overrun + 전체 페이지수 plumbing(`SORT_PARAM`, `sort_split_last_run`) | 60–100 |
| `sort_put_result_for_parallel` SORT_GROUP_BY 분기 + ORDER_BY 골격 합류 + coda | 50–80 |
| 직렬 폴백 게이트 5종 + `SORT_LISTFILE_PX_ARG` 필드 + 두 호출부 | 40–60 |
| A6 finalize px 통계 + `query_dump.c` 방출 + 워커 통계 합산 | 40–60 |
| **합계** | **390–600** (하드스톱 420 초과) |

대조: px_scan의 복제 배관만 떼어도 `clone_xasl` 75줄(`px_scan_task.cpp:569-643`) + 해제 24줄(`:495-518`)
+ vd 복제 23줄(`px_scan.cpp:1642-1664`) ≈ 122줄이며, 이는 이미 task/manager 프레임워크가 있는 곳에서
`xcache`/`stx_map_stream_to_xasl`을 **재사용**한 수치다. 정렬 drain 문맥에는 그 프레임워크가 없다.

## 3. Correctness (§6-b, all five mandatory checks)

전부 **미수행 — 대상 없음**(처치가 없어 before/after 비교가 성립하지 않는다). 정합성 실패는 발생하지
않았고, 발생할 코드도 없다.

| # | 검사 | 처분 |
|---|---|---|
| 1 | 변경 경로 단위/회귀 TC | N/A — 변경 경로 없음 |
| 2 | 타깃 질의 | N/A |
| 3 | `q_relations` 전 질의 | N/A |
| 4 | Q01–Q22 결과 스모크 | N/A |
| 5 | 스트레스 + 진단(OptDebug) 빌드 | N/A — D6 게이트 미도달 |

부수적으로 D1 프로브 중 Q15 뷰 객체 정리 조항만 만족했다: 실행 전 `db_class` count 0, 실행 후 0.

## 4. §A 착수 전 소스검증 A1–A8 — 전문

핀 소스 `61f4b4cf9` 스택에서 **첫 소스 수정 전** 전수 검증. 상세: `A1-A8-source-verification.md`.

| # | 가정 | 기대 | **판정** | 근거 |
|---|---|---|---|---|
| A1 | consolidated run 임시파일의 페이지 경계 = 튜플 경계 | holds | **holds** | `external_sort.c:3294-3384` — 페이지 단위로 읽고 페이지별 slot table에서 `sort_spage_get_record`(`:3330`)로 꺼낸다 ⇒ 레코드가 페이지를 걸칠 수 없다. long record는 `REC_BIGONE` + `sort_retrieve_longrec`(`:3338-3346`)로 이미 처리 |
| A2 | `sort_put_result_from_tmpfile`가 임의 `start_index`에서 시작 + 조건부 정지를 지역 수정으로 수용 | holds | **holds** (필드 1개 추가 필요) | 시그니처가 이미 `(…, int start_pagenum)`(`:3295`)이고 `current_pages = start_pagenum`(`:3298`). ORDER_BY가 이미 `file_contents[0].start_index`를 전달(`:5305`). overrun은 consolidated run 전체 페이지 수가 필요해 `SORT_PARAM`에 필드 1개 추가 |
| **A3** | `GROUPBY_STATE` 워커별 복제 가능 | holds | **반증 → stop-and-report** | §4-a |
| A4 | 직렬 폴백 게이트 조건이 게이트 시점에 판별 가능 | enumerable | **holds** — 5조건 전수 열거 | §4-b |
| A5 | qfile 연결 coda가 group-by 출력에서도 순서 보존 | holds | **holds** | ORDER_BY coda `:4907-4947` = `qfile_connect_list`(`:4934`) / `qfile_append_list`(`:4924`, `FILE_QUERY_AREA`) / `qfile_reopen_list_as_append_mode`(`:4943`). 모두 `QFILE_LIST_ID` 수준이라 group-by 출력에도 동일 적용 |
| A6 | `GROUPBY_STATS`에 finalize 국면 px 통계 확장 수용 | holds | **holds** | `struct groupby_stat` = `query/xasl.h:987-1003`. `stream_to_xasl.c:2383`에서 `memset`만 하고 `xasl_to_stream.c`에 pack 코드가 없다 ⇒ **런타임 전용, XASL 직렬화 무접촉**. 방출은 `query_dump.c:3376-3377`(JSON) / `:3973`(text) |
| A7 | 워커 스레드 문맥에서 집계·finalize 호출 안전 | holds | **조건부 holds** (A4 게이트 전제) | 워커 preamble이 `tran_index`/`m_px_orig_thread_entry`/`conn_entry` 승계 + `push_resource_tracks`(`:5273-5277`, 해제 `:5336`), 에러는 `main_error_context` swap(`:5339-5344`, 단 실패 워커 1개분). 그러나 finalize의 `qexec_execute_mainblock`(HAVING 서브쿼리, `query_executor.c:19927`)과 `qexec_add_composite_lock`(`:20034`)은 리더 전용 전제 ⇒ A4 게이트로 배제 필요 |
| A8 | phase ① 예약 워커를 ③ drain에 재사용 | holds | **holds** | `SORT_EXECUTE_PARALLEL`(`query/parallel/px_sort.h:41-49`)은 `sort_check_parallelism`(`external_sort.c:5244-5246`)이 예약한 `px_worker_manager`에 태스크를 push. ORDER_BY가 이미 `:4900`에서 ③ drain에 재사용 |

### 4-a. A3 반증 — 근거 `file:line`

복제 **가능**한 부분: 차원별 누산기(`qexec_gby_init_group_dim`이 이미 `AGGREGATE_TYPE`를 memcpy 후
`accumulator.value`/`value2`를 `db_value_copy` — `query_executor.c:20258-20283`, 해제 `:20299-20332`),
워커별 출력 리스트, 작업 버퍼(`current_key`/`gby_rec`/`input_tpl`/`output_tplrec`, 구조체 `:242-245`).

복제 **불가능**한 리더 전역 은닉 상태 — 전수 열거:

| # | 상태 | `file:line` | 왜 복제 불가인가 |
|---|---|---|---|
| 1 | 공유 `g_val_list` / `g_regu_list` 인스턴스 | `query_executor.c:4587` (`fetch_val_list (…, gbstate->g_regu_list, &gbstate->xasl_state->vd, …, tpl, peek)`), 읽기 `:4597` (`qdata_evaluate_aggregate_list`) | 튜플마다 **XASL 소유 DB_VALUE에 기록**하고 같은 값을 operand로 읽는다. 워커 2개가 동시에 수행하면 즉시 data race + 오답. A3가 반증 예시로 명시한 항목 그 자체 |
| 2 | `g_output_agg_list` (= XASL `buildlist->g_agg_list`) | `:19947-19948` (`pr_clear_value (g_outp->accumulator.value); *g_outp->accumulator.value = *d_aggp->accumulator.value;`) | 이 DB_VALUE가 outptr/having regu 트리의 **바인딩 지점**이라 사적 복제로 대체 불가(복제해도 regu 트리는 원본을 가리킨다) |
| 3 | `having_pred` / `g_outptr_list` / 공유 `xasl_state->vd` | `:19973` (`eval_pred`), `:20047-20048` (`qexec_generate_tuple_descriptor`), `:20081` (`qdata_copy_valptr_list_to_tuple`) | 공유 regu 트리와 공유 `VAL_DESCR`에서 평가되며 regu 평가는 노드별 scratch DB_VALUE에 기록한다 |
| 4 | `agg_hash_context` 부분리스트 커서 | `:5191-5228`, `:5250-5309` (커서 로드 `:5626-5638`, 부재 시 `S_END` `:5643`) | 그룹 경계와 lock-step으로 소비되는 **단일 순차 커서**. XASL을 복제해도 복제본 컨텍스트는 비어 있어 리더의 spill 산출물을 대신하지 못한다 |
| 5 | `grbynum_val` + `SORT_PUT_STOP` 단발 발화 / `groupby_stats.rows++` / `composite_lock` | `:19987-20019`, `:20101`, `:5662-5673` + `:20028-20042` | 전역 카운터·전역 락. STOP은 전역 경계에서 정확히 한 번만 발화해야 한다 |

**스펙 D4의 설계 전제("ORDER_BY 병렬 분기 미러링")가 성립하지 않는다:**

- ORDER_BY의 병렬 drain put_fn `qexec_ordby_put_next`(`query_executor.c:3772-3900`)는 **순수 튜플 복사**다
  (`qfile_add_tuple_to_list (…, info->output_file, data)` `:3878`). XASL 표현식 평가·집계·HAVING·출력튜플
  생성이 없다. 평범한 ORDER BY는 put_fn이 아예 NULL이다(`:4258`).
- 결정이 이미 소스에 적혀 있다 — `external_sort.c:5720-5722`:
  *"ORDER_WITH_LIMIT: fan-in only, then serial put via put_fn … put_fn must not run in parallel because
  ordbynum_val state is shared and SORT_PUT_STOP must fire exactly once at the global LIMIT boundary."*
  `ordbynum_val` **하나** 때문에 ORDER 계열도 직렬 drain으로 내려간다. GROUP_BY의 put_fn은 그보다
  훨씬 큰 공유 상태(위 1~5)를 갖는다.

**복제 기계장치는 존재하지만 반경 밖이다**: 병렬 scan은 워커별 XASL 전체 복제로 해결한다 —
`px_scan_task.cpp:569-643` (`xcache_find_xasl_id_for_execute` + `xasl_find_by_id`, 또는
`stx_map_stream_to_xasl`로 packed XASL 재해석; 둘 다 `main_thread_p->m_px_lock_mutex` 보호) + 워커별
`xasl_state`/`VAL_DESCR`(`pr_clone_value`) `:616-641`, 정리 `:495-518`. 이를 도입하면 §5-d의
"unanticipated subsystem / XASL serialization"에 정면으로 걸린다.

독립 red-team이 `grep`으로 반경 내 대체 복제 기계장치(REGU_VARIABLE_LIST/VAL_LIST deep-copy, 반경 내
per-thread `VAL_DESCR` 헬퍼, operand까지 rebind하는 aggregate-list clone)를 탐색해 **부재**를 확인했다.

### 4-b. A4 — 직렬 폴백 게이트 조건 전수 (판별 가능)

`qexec_groupby`가 `sort_listfile (…, SORT_GROUP_BY, &gby_px)`(`:5686-5688`)를 호출하기 **전에** 전부 판별된다.

| # | 조건 | 판별식 |
|---|---|---|
| ① | ROLLUP / Data Cube | `buildlist->g_with_rollup`(`:5405`) → `g_dim_levels > 1`(`:20225-20229`) |
| ② | HAVING 서브쿼리 | `buildlist->eptr_list != NULL`(`:5403`) — finalize가 워커 문맥에서 `qexec_execute_mainblock`(`:19925-19933`) 호출 |
| ③ | GROUPBY_NUM / LIMIT | `buildlist->g_grbynum_val != NULL`(`:5402`) |
| ④ | MULTI_UPDATE_AGG (composite lock) | `XASL_IS_FLAGED (xasl, XASL_MULTI_UPDATE_AGG)`(`:5662`) |
| ⑤ | 해시 부분리스트 병합 활성 | `agg_hash_context->part_scan_code == S_SUCCESS` — 값이 `:5633-5638` 또는 `:5643`에서 확정 |

전달은 `SORT_LISTFILE_PX_ARG`에 필드를 추가하고 `sort_check_parallelism`의 SORT_GROUP_BY 분기
(`external_sort.c:5228-5247`, 현재 `px->hash_eligible`만 검사)에서 게이트하면 된다. 게이트 시 기존
직렬 경로(`sort_run_final_single`, `:5851`)를 그대로 타므로 회귀 반경은 0이다.

## 5. D1 귀속 프로브 결과

보존된 `install/IMP-015` 바이너리(재빌드 없음)로 실행. **라벨: 귀속 증거이며 A/B 증거가 아니다** —
§6-c 블록 규율과 quiet-gate 차단 미적용, bgload는 기록만. 상세: `D1-attribution-report.md`.

프로브 계약 준수 기록: conf sha256 `ad19f5ac…` 일치, `CUBRID_TMP` = 캠페인 경로 어서션 통과,
§3-b ownership `FREE`→`OK`(`executable_under_campaign_prefix=true`), all-TID affinity 126 TID
`off_sut_tids=[]`, bgload `CLEAN`(mean 0.384 / p95 0.67 / max 0.882 core-s/s, 차단에 사용하지 않음),
종료 시 서버 정지 및 `cub_server` 부재 확인. 프로브 시작 전 §6-a-2 핀을 위반한 잔존 campaign-owned
`cub_master`(PID 3221464, `CUBRID_TMP=/home/cubrid/CUBRID/var/CUBRID_SOCK`, 부착 서버 0개)를 소유권
증명 기록 후 정지했다(`probe/master-cleanup.txt`). 타 사용자 프로세스는 건드리지 않았다.

1차 기록은 `--call-graph lbr`이었으나 이 호스트(perf 4.18 / kernel 6.9)에서 콜체인이 얕아 포괄 귀속
최대치가 1.68%에 머물러 사용 불가였고, 동일 문장을 `--call-graph dwarf,2048 -F 99`로 재기록해 귀속에
사용했다. 두 기록 모두 보존한다.

### 5-a. Q15 (1차 게이트 타깃) — 표적 국면 **미발동**

트레이스(`probe/q15-trace.out`): 두 GROUPBY 노드 모두 `hash: partial`(= `HS_REJECT_ALL`,
`query_dump.c:3948-3950`)인데도 **`(parallel workers: …)` 서브라인이 없다**.

DWARF 콜체인 표본 **5,088**개 중:

| 심볼 | 표본 |
|---|---|
| `sort_put_result_from_tmpfile` (**③**) | **0** |
| `sort_merge_nruns` (**②**) | **0** |
| `sort_end_parallelism` | **0** |
| `qfile_sort_get_next_parallel` | **absent** |
| `sort_listfile_execute` (phase ① 워커 진입) | **absent** |
| `sort_exphase_merge` (직렬 병합/드레인) | 379 |
| `qexec_gby_put_next` | 299 |

포괄 비율: `sort_listfile` 10.00%, `sort_exphase_merge` 8.24%, `qexec_gby_put_next` 6.51%,
`sort_inphase_sort` 2.41%. ⇒ **Q15의 group-by 폴백 정렬은 IMP-015 하에서도 완전 직렬**이고, 정렬 비용
전부가 고전적 직렬 경로에 있다.

인라인 내구성 확인(독립 red-team): `nm`/`objdump`로 `sort_run_final_single`과
`sort_merge_worker_runs_to_one`이 **인라인되어 심볼이 사라질 수 있음**을 확인했고, 그럼에도 Q15 판정은
인라인 무관 신호(`sort_end_parallelism`, `sort_listfile_execute`, `qfile_sort_get_next_parallel`,
트레이스 `parallel workers` 서브라인, 스레드/comm 분포)로 성립함을 검증했다.

원인 절단 실험:

| 실험 | 입력 | 결과 |
|---|---|---|
| 뷰 본문 단독 (3개월 창) | 2,265,714행 / sort page 18,299 | **직렬** |
| 뷰 본문 12개월 창 | 9,123,688행 / sort page 85,534 | **직렬** |

⇒ 크기 문턱(`sort_page_threshold` 2048)·상위 질의 구조·해시 상태 **전부 원인 아님**.

### 5-b. Q18 (관측 타깃) — 병렬은 발동하지만 **다른 정렬**이고, 그 안에서 ③:② ≈ 87:13

표본 **10,684**개:

| 심볼 | 표본 | 비율 |
|---|---|---|
| `sort_put_result_from_tmpfile` (**③**) | 716 | 6.70% |
| `sort_end_parallelism` | 716 | 6.70% |
| `sort_merge_nruns` (**②**) | 103 | 0.96% |
| `sort_exphase_merge` (직렬) | 1,700 | 15.91% |
| `qexec_gby_put_next` (메인 group-by put_fn) | 1,203 | 11.26% |
| `qexec_hash_gby_put_next` (부분 해시리스트 put_fn) | 690 | 6.46% |
| ③ ∧ `qexec_gby_put_next` | **0** | 0.00% |
| ③ ∧ `qexec_hash_gby_put_next` | **688** | 6.44% |

- **③ / (②+③) = 716 / 819 = 87.4%** ⇒ 스펙 D4의 "③ 지배" 가정 자체는 **참**이다.
- 그러나 그 ③는 **해시 부분리스트 정렬**의 drain이다(③ 표본 716 중 688이 `qexec_hash_gby_put_next`와
  동시 출현, `qexec_gby_put_next`와는 **0**). 스펙 D4가 지목한 메인 group-by 정렬(put_fn
  `qexec_gby_put_next`)은 Q18에서도 **직렬**이다(`sort_exphase_merge` 1,700 아래 `qexec_gby_put_next` 1,203).
- 즉 IMP-015가 실제로 병렬화한 것은 그 변경 (b) — 부분 해시리스트 정렬의 무조건 병렬 적격화 — 이다.

### 5-c. `UNPROVABLE_ON_THIS_HOST` 판정 (Q15)

스펙 D1의 산정 규율: 기대치 = **프로브로 측정된 리더 잔여 × 논증된 제거가능 분율(Amdahl)**. 구 레짐
밴드·이종 경로 절대치 이관 금지.

- Q15의 측정된 리더 잔여(②+③) = **0.00%** (§5-a: ③ 0표본, ② 0표본, `sort_end_parallelism` 0표본).
- ⇒ 어떤 Amdahl 분율에서도 **기대효과 = 0.00%**.
- MDE: §6-d-1 corrected MDE가 Q15에 대해 **존재하지 않는다**
  (`restart-variance-calibration.json`의 `queries_not_covered_at_all`에 Q15 포함, Phase 1A 미실행).
  IMP-015 §5와 동일한 **라벨링된 restart-regime 대체 MDE**를 쓰더라도 §6-d의 하한
  `MDE = max(1%, 2 × CV)` 때문에 **어떤 경우에도 ≥ 1%**다(IMP-015가 Q10에 쓴 대체값 1.42%).
- ⇒ `0.00% < 1%` ⇒ **`UNPROVABLE_ON_THIS_HOST`**. 이 판정은 대체 MDE의 정확한 값에 의존하지 않는다.

프로브 wall(참고용, A/B 아님): Q18 traced 37.94 s / dwarf 37.52 s, Q15 traced 10.88 s / dwarf 10.94 s.

## 6. Before/after timings

**없음.** P 바이너리가 존재하지 않아 §6-c `B → P → P → B` 블록을 **한 번도 실행하지 않았다**
(측정 예산 미소모).

## 7. Paired statistics (§6-d)

**없음.** paired block-median ratio / bootstrap 95% CI / pair count 미산출. Q15의 MDE는 §5-c에 기술한
대로 하한 1%만 사용했다.

## 8. Plan and work-volume stability (§7-d)

플랜 모양·작업량 변화 없음(코드 변경 없음). `A/B_CONFOUNDED_PLAN_CHANGE` 해당 없음.

## 9. CPU, TWU and profile

TWU/serial_tail의 공식 텔레메트리 비교는 스펙 §C에 따라 cumulative-phase로 이월된 항목이며 이 IMP에서는
프로브 수준 귀속 증거로 대체했다(§5). 처치가 없으므로 움직인 프로파일 밴드는 없다. 프로브가 관측한
Q18 포괄 분포: `qexec_hash_gby_agg_tuple` 39.39%, `sort_listfile` 21.02%, `sort_exphase_merge` 16.87%,
`qexec_gby_put_next` 11.98%, `sort_end_parallelism` = `sort_put_result_from_tmpfile` 7.21%,
`qexec_hash_gby_put_next` 6.95%, `sort_listfile_execute` 3.72%, `qexec_groupby` 2.84%.

## 10. Expected versus measured effect (§7-e)

스펙 §B 항목 1의 가설: "IMP-015 이후 group-by 폴백 정렬의 잔여 병목은 리더 직렬 국면(②+③)이며, 그중
③을 그룹 경계 정렬 분할로 병렬화하면 Q15 wall이 줄어든다."

- **지지된 부분**: 병렬 폴백 정렬이 실제로 발동하는 인스턴스에서 ③이 ②를 87.4:12.6으로 압도한다.
- **반증된 부분**: **Q15에서는 병렬 폴백 정렬 자체가 발동하지 않는다.** "IMP-015 이후의 잔여"라는
  전제가 Q15에 대해 거짓이다.
- §7-e가 요구하는 근본원인 재검토: 원 증거 귀속(카드의 69.8%/50.1% 밴드, 구 측정 레짐)이 Q15에 대해
  **잘못된 지점을 지목**했다. AMEND-F가 성문화한 "프로파일 밴드는 자동으로 제거가능 효과가 아니다"의
  실례이며, 스펙 D1이 착수 전 프로브를 요구한 이유가 정확히 이것이다 — 프로브가 구현 **전에** 이를 잡았다.

## 11. Regressions (non-target queries)

측정 없음, 회귀 0건 — 코드 변경이 없으므로 회귀가 발생할 수 없다. Q10 비대칭 가드(IMP-015가 확보한
−9.92%)는 이 IMP로 위협받지 않는다. Q11/Q16/Q01/Q03/Q05 부정 컨트롤도 실행 대상이 아니었다.

## 12. Verdict

**`stopped`** — `A3-refuted; UNPROVABLE_ON_THIS_HOST on Q15`. 결정: 사용자 지시 2026-08-04
(authority order 1), §11-a 에스컬레이션에 대한 응답.

**왜 `accepted`/`rejected`가 아닌가**:

- §7-a(accepted)의 기준 1·2는 측정 자체가 없어 평가 불가이고, 기준 3(point improvement ≥ MDE)과
  기준 4(기대 metric signature 이동)는 **원리적으로 불가능**하다(기대효과 0%, 신호를 낼 국면이 미실행).
- §7-c(rejected)의 네 기준은 모두 **측정 사건**을 전제한다 — 정합성 실패, 성능 열화, 신호 부동,
  관련 질의 3% 초과 회귀. P 바이너리가 없어 그중 어느 것도 *측정된 바 없다*. 따라서 `rejected` 라벨은
  실제로 일어난 일을 잘못 기술한다.
- §7-b(inconclusive)도 아니다 — pair를 수집한 적이 없고, 수집해도 효과가 0으로 논증된다.
- 실제로 일어난 일은 **구현 착수 전 스펙 규정 정지**다: 스펙 §A가 A3 반증을 stop-and-report로,
  스펙 D1이 MDE 미달을 `UNPROVABLE_ON_THIS_HOST` + 착수 재문의로 규정했고 둘 다 발동했다.
  그래서 verdict를 `stopped`로 기록한다.

보존 상태: 브랜치는 `61f4b4cf9`에 자체 커밋 0개로 남아 있고 worktree도 clean하게 보존한다.

## 13. Raw evidence index

형식: `claim → raw file → method → evidence type → sha256(앞 16)`

| claim | raw | method | type | sha256 |
|---|---|---|---|---|
| Q15 group-by 폴백 정렬 직렬 (GROUPBY에 parallel workers 부재) | `probe/q15-trace.out` | SET TRACE ON 1회 | trace | `2d772f05247d1f5c` |
| Q15 ③/② 표본 0 | `probe/q15.chaincounts.txt` | `perf script` 표본별 콜체인 심볼 계수 | perf-derived | 매니페스트 |
| Q15 병렬 심볼 absent | `probe/q15.phase-attrib.txt` | `perf report -g none --children --sort symbol` | perf-derived | 매니페스트 |
| Q18 ③ 716 / ② 103, ③∧hash_gby 688 / ③∧gby 0 | `probe/q18.chaincounts.txt` | 동일 계수법 | perf-derived | 매니페스트 |
| Q18 병렬 발동 + 워커 6 | `probe/q18-trace.out` | SET TRACE ON 1회 | trace | `dfe4af21f99d2d55` |
| 크기 원인 배제 (12개월 창도 직렬) | `probe/q15diag.out` | 행수 2,265,714 / 9,123,688 + 트레이스 | trace | `3276d40f03a1feef` |
| 상위 구조 원인 배제 (뷰 본문 단독) | `probe/q15body-trace.out` | 트레이스 | trace | `39a33fe1278366b8` |
| 원 perf 표본 | `probe/q15.dwarf.perf.data` / `probe/q18.dwarf.perf.data` | `perf record -F 99 --call-graph dwarf,2048 -p <cub_server>` | perf-sample | `81de5d817755b568` / `3a7699a3bcf4467e` |
| A3 반증 소스 근거 | `worktrees/IMP-032/src/query/query_executor.c:4587,4597,19947-19948,19973,20047-20048,20081` + `src/storage/external_sort.c:5720-5722` | 핀 소스 판독 | source | branch `61f4b4cf9` |
| 프로브 계약 준수 | `probe/{preflight.txt,identity-*.json,bgload-*.json,master-cleanup.txt,server-*.txt}` | conf sha256 / all-TID / §3-b ownership / bgload | verification | 매니페스트 |
| 증거 무결성 (C7 규명) | `status/C7-report.md`, `closeout/c7-drift-analysis.json` | gen1 매니페스트 38건 전수 재해시 | verification | 커밋 내 |
| 독립 재계수 (red-team) | `closeout/redteam/redteam-report.json`, `redteam-report-gen2.json` | 자체 파서 재도출 + `nm`/`objdump` 인라인 확인 | test-report | 매니페스트 |
| 종료 검증 15/15 | `closeout/verify-report.json` | `closeout/verify_closeout.py` (연속 2회 동일 해시) | test-report | — (자기참조라 매니페스트 제외) |
| 전 산출물 지문 | `raw-manifest.json` | 산출물별 sha256 | manifest | 커밋 내 |

## 14. Branch, commit and build IDs

| 항목 | 값 |
|---|---|
| branch | `impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize` (자체 커밋 0) |
| **B** — 스펙 D3에 따라 캠페인 base가 아니라 IMP-015 보존본 | `install/IMP-015/bin/cub_server` sha256 `0a376e0606f7395822cf0f4925b8290326b4f1131e6c865e5e7b291722726f30`, ELF Build ID `379ab8c0760ec526fbeee8b80f0a2da0d81759bd`, **재빌드 없음** |
| **P** | **없음** |
| runtime conf | sha256 `ad19f5ac1e7e983e4a0b1c113d21e25e096d02d3160445f9d10a2e8b6d9cb9ff` (§6-a-2 핀, 프로브 블록에서 검증) |

### 14-a. 기록 자체에 대한 종료 검증 코호트

기각/정지 기록도 검증 대상으로 삼았다. 동결 스냅샷의 `sourceHash`와 경로별 sha256은
`closeout/verify-report.json`이 보유한다(이 문서에 적으면 자기참조).

| lane | 결과 |
|---|---|
| cleaner (ai-slop-cleaner) | BLOCKING 2건 → 리더 수정(죽은 필드 `verdict_absent_reason` 제거, 결정 이전 시제 표현 정정). advisory 3건은 보고서에만. `closeout/ai-slop-cleanup-report.md` |
| 기계 검증 | `closeout/verify_closeout.py` **15/15**, 연속 2회 동일 `sourceHash`. 초기 실행에서 2개 체크가 실제로 실패해(문자열 오매칭, `pgrep` 자기매칭) 수정한 이력 — 하네스가 실패를 가리지 않는다는 증거 |
| architect (read-only, gen2) | architecture/product/code = WATCH/WATCH/WATCH, recommendation COMMENT, **blockers 없음** |
| executor QA / red-team (gen1) | **passed, 반증 0건.** Q15 5,088/0/0, Q18 10,684/716/103/1,203/1,700/688/0 전부 독립 파서로 재도출 일치 |
| executor QA / red-team (gen2) | 델타 6건 중 5 통과 + **정밀도 blocker 1건** → 반영 완료: 계수 caveat이 "판정 심볼에 접두사 충돌이 없다"고 과장했으나 실제로 `sort_merge_nruns` ⊂ `sort_merge_nruns_queue_cb`, `sort_exphase_merge` ⊂ `sort_exphase_merge_elim_dup` 충돌이 존재한다. 수치 영향은 표본별 대조로 0임이 확인됐고, caveat을 "충돌이 이 수치를 흔들지 않음을 표본별로 검증했다"로 재기술했다 |

## 15. Notion sync state

대상: IC-5/IMP-032 카드 `3adf947f-1be1-81e8-acb5-f583ec2e4a2a` (사용자 지정). 상태는
`notion_backfill_pending.jsonl`의 live 레코드가 보유한다.

이 호스트에는 Notion 쓰기 수단이 **없다** — `~/.gjc/agent/config.yml`에 MCP 서버 미구성, `ntn` CLI가
`PATH`/`~/.bun/bin`/`~/.local/bin`/`/usr/local/bin`/global node_modules/`.claude/skills` 어디에도 없음.
§10-c는 원격 워커의 Notion 쓰기를 금지하고 컨트롤러가 Notion 가능한 subagent를 디스패치하도록 규정하는데,
이 머신에서 스폰되는 subagent도 동일한 빈 툴셋을 물려받는다. 따라서 §10-f에 따라 **완전한 payload를 담은
idempotent 백필 레코드**를 기록했다(포인터 아님). §10-e discovery 필드
(`Priority`/`Difficulty`/`Expected effect`/`Root cause`/`CUBRID source`/`PostgreSQL source`/
`Evidence level`/`Evidence event`/`Category`/`Queries`/`Status`)는 **불가침**이며 payload에 포함하지 않았다.
payload는 §10-d 손상 스캔(literal `\n` 0, 고립 `n` 토큰 0, escaped table 0)을 통과했다.

## 16. IMP-015와의 관계 — 오해 방지

| | IMP-015 | IMP-032 (구 IC-5) |
|---|---|---|
| 상태 | **구현 완료 / accepted (provisional)** | **stopped** (구현 착수 전 정지) |
| 소스 변경 | `query_executor.c` 27 ins / 2 del (1 파일) @ `61f4b4cf9` | **0** |
| 측정 | Q10 −9.92%, CI [0.8991, 0.9223] | 없음 (A/B 미실행) |
| 관계 | IMP-032의 base (스펙 D2 스태킹, 사용자 승인, §5-b에 따라 양쪽 report에 기록) | IMP-015 **이후에 더 밀어보려던 후속 시도** |

**IMP-032의 정지는 IMP-015의 verdict를 바꾸지 않는다.** 다만 프로브가 IMP-015의 **적용 범위를 좁히는**
사실을 확보했고 IMP-015 report §14-a에 기록했다: (i) Q15에서는 IMP-015의 런타임-진실 게이트가 병렬
경로를 열지 못한다(IMP-015 §9의 Q15 +1.0% 무효과와 정합), (ii) Q18에서 실제로 병렬화된 것은 변경 (b)
(부분 해시리스트 정렬의 무조건 병렬 적격화)이고 메인 group-by 폴백 정렬은 여전히 직렬이다.

## 17. Carried — 신규 발견 (미진단, 이 IMP 범위 아님)

**메인 group-by 폴백 정렬이 IMP-015 하에서도 병렬 게이트를 통과하지 못한다.** 크기는 Q15 정렬 비용
전부(`sort_listfile` 10.00% of 서버 cycles)와 Q18의 `sort_exphase_merge` 16.87%로, IMP-032가 노렸던
③(Q18 기준 6.70%)보다 **크다**.

배제된 원인: 입력 규모/페이지 문턱(9.1M행·85,534 sort page에서도 직렬), 해시 상태
(`hash: partial` = HS_REJECT_ALL이므로 첫 게이트 통과), 상위 질의 구조(뷰 본문 단독도 직렬).

남은 후보 (확정에는 계측 빌드 = 첫 소스 수정이 필요하므로 정지 상태에서 수행하지 않았다):

1. `sort_check_parallelism`(`external_sort.c:5236-5246`)이 보는 `input_list->page_cnt`가 gather된
   mergeable-list 입력에서 문턱(2048) 미달로 관측되는 경우.
2. `px->parallelism`(= `xasl->parallelism`) 힌트가 해당 XASL 노드에서 `0 또는 1`이어서
   `compute_parallel_degree`가 즉시 0을 반환하는 경우 —
   `px_parallel.cpp:128-131` *"hint >= 0 and < start_degree disables parallel execution"*.
3. `try_reserve_workers` 실패.

신규 IMP ID 발급은 §1-b에 따라 **사용자 지시로만** 가능하므로 여기서는 carried 항목으로 기록만 한다
(편입 시 next_id는 `IMP-033`).

## §8-c 최종 상태 블록

`status/final-status.yaml`이 정본이며 동일 내용을 여기 옮긴다.

```yaml
TPCH_SSPQ_IMPL_STATUS:
  campaign_id: tpch-sspq-impl-r1-20260803
  imp_id: IMP-032
  impl_ssot_commit: 276d8e866f0f4702648ccb9b8c00c8c5410931e9
  impl_ssot_blob_sha: 15b42ddca521444fa54b34b0fa8477ed2df643f6
  session_id: 019fc85d-8da5-7000-bc9e-7f97de474072
  stage: IMP_COMPLETE
  state: complete
  branch: impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize
  verdict: stopped
  verdict_detail: A3-refuted; UNPROVABLE_ON_THIS_HOST on Q15
  source_modified: none
  ab_budget_spent: none
```
