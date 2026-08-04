# Q15 group-by 폴백 정렬 병렬 미발동 — 원인 규명

**라벨: 진단·귀속 증거(diagnostic / attribution evidence)이며 성능 A/B 증거가 아니다.**
IMPL-SSOT §6-c 블록 규율(`B→P→P→B`, 3 measured runs)과 quiet-gate 차단을 적용하지 않았고, bgload는
기록만 했다. 재빌드 없음 — 보존 `install/IMP-015` 바이너리만 사용했다. 소스 수정 0건, gdb 미사용,
진단/계측 빌드 미생성. **이 문서의 어떤 수치도 성능 A/B 결과로 인용해서는 안 된다.**

## 0. 계약과 환경 (기록)

| 항목 | 값 |
|---|---|
| 캠페인 | `tpch-sspq-impl-r1-20260803` |
| 작업 | handoff 작업 2 (Q15 병렬 미발동 진단, 읽기 전용) · `imp_id: BASELINE` |
| IMPL-SSOT | commit `eccdd1ae58cd733ed3121585146d68b9ae54a73f`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` (1653행, AMEND-A..G) — §1-d 검증 통과 |
| 읽은 소스 (base) | `/home/cubrid/dev/tpch-sspq-impl-r1/base-src` @ `607f1ee9fb2394de129e083602c84a6525fc685c` |
| 읽은 소스 (patched) | `/home/cubrid/dev/tpch-sspq-impl-r1/worktrees/IMP-015` @ `61f4b4cf967dbc2f0cd18422b83561ef44366382` |
| 프로브 바이너리 | `install/IMP-015/bin/cub_server` sha256 `0a376e0606f7395822cf0f4925b8290326b4f1131e6c865e5e7b291722726f30`, Build ID `379ab8c0760ec526fbeee8b80f0a2da0d81759bd` |
| runtime conf | `install/IMP-015/conf/cubrid.conf` sha256 `ad19f5ac1e7e983e4a0b1c113d21e25e096d02d3160445f9d10a2e8b6d9cb9ff` = §6-a-2 핀 일치 |
| `CUBRID_TMP` | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/tmp` (§6-a-2 어서션 통과) |
| CPU / NUMA | SUT `taskset -c 0-15` + `numactl --membind=0` (§3-a), 프로세스 시작 시점 적용 |
| all-TID affinity | 126 TID, `n_off_sut=0` |
| §3-b ownership | `OK` (`executable_under_campaign_prefix=true`, port 1523, db `tpch_sf10_q1`, server pid 3276480) |
| bgload (기록만) | start mean 0.514 / p95 0.868 / max 1.859 core-s/s `CLEAN`; end mean 0.415 / p95 0.629 / max 1.045 `CLEAN` (threshold 6.0은 **차단에 사용하지 않음**) |
| 드라이버 | 자식 tmux `tpch-sspq-impl-r1-20260803-q15diag` (worker-owned driver, §8-b), `nohup`/`setsid` 미사용 — `work/BASELINE/q15-diagnosis/driver-record.json` |
| 정리 | 프로브 종료 후 `cub_server` 정지 확인, 잔존 `install/IMP-015` `cub_master`(pid 3231627)를 §3-b 근거 기록 후 정지 — port 1523 free |

## 1. 규명해야 했던 것

IMP-032 D1 프로브의 발견(`tpch-sspq/impl/IMP-032/report.md`, `probe/D1-attribution-report.md`):
Q15는 IMP-015 바이너리에서 두 GROUPBY 노드 모두 트레이스가 `hash: partial`인데도 group-by 폴백 정렬의
병렬 경로가 **한 번도 발동하지 않는다**(perf 5,088 표본 중 ③ `sort_put_result_from_tmpfile` 0개,
② `sort_merge_nruns` 0개, `sort_end_parallelism` 0개). 입력 규모(9,123,688행 / sort page 85,534),
상위 질의 구조(뷰 본문 단독도 직렬), 해시 상태는 원인에서 배제되었고, 남은 후보 셋은
`input_list->page_cnt` 문턱 미달 / `px->parallelism` 힌트 0·1 / `try_reserve_workers` 실패였다.

D1이 확정하지 못한 이유는 "계측 빌드가 필요하다"고 판단했기 때문이다. **계측 빌드는 필요하지 않았다.**
아래 §3의 힌트 대조쌍이 소스 수정 없이 원인을 단정한다.

## 2. 원인 — `file:line`

### 2-a. 한 줄 요약

병렬 heap scan의 **mergeable-list gather 경로에서는 리더가 자기 해시 패스를 아예 실행하지 않는다.**
따라서 리더의 `agg_hash_context->state`는 초기값 `HS_ACCEPT_ALL`에 머무는데,
트레이스의 `hash: partial` 라벨은 그 경로에서 **무조건 강제 대입**된다. 게이트가 읽는 필드와 트레이스가
찍는 필드가 서로 다른 필드이고, 바로 이 경로에서 둘이 불일치한다. 그 결과
`sort_check_parallelism()`은 크기·차수·워커를 보기 **전에**
`external_sort.c:5232`에서 즉시 `return 1`(직렬)한다.

### 2-b. 인과 사슬 (모두 핀 소스에서 확인)

| # | 위치 | 내용 |
|---|---|---|
| 1 | `src/query/parallel/px_scan/px_scan_result_handler.cpp:99` | `m_.g_hash_eligible = orig_xasl…proc.buildlist.g_hash_eligible` — 플랜타임 해시 적격성을 리더에서 읽어둔다 |
| 2 | 같은 파일 `:286`, `:291` | 워커마다 `tl.xasl = curr_xasl`(XASL **클론**)이고 `qexec_alloc_agg_hash_context_buildlist_xasl(…, curr_xasl, …)`로 **워커 전용 `agg_hash_context`**를 따로 할당한다. 클론은 `px_scan_task.cpp:570-585 clone_xasl()`이 `xcache_find_xasl_id_for_execute()`로 얻는다 |
| 3 | 같은 파일 `:839`, `:846` | 해시 집계는 워커에서 `qexec_hash_gby_agg_tuple_public(…, tl.xasl, …)`로 수행되고, 상태는 `tl.agg_hash_state = tl.xasl->proc.buildlist.agg_hash_context->state`로 **워커 로컬**에 기록된다 |
| 4 | 같은 파일 `:417`, `:628`, `:633` | 워커 결과는 `writer_results` → 리더의 `xasl->list_id`로, 워커 spill 부분리스트는 `hgby_results` → 리더의 `agg_hash_context->part_list_id`로 **병합**된다 |
| 5 | 같은 파일 **`:635`** | `m_.orig_xasl->groupby_stats.groupby_hash = HS_REJECT_ALL;` — 주석 그대로 *"HS_REJECT_ALL **forces** 'hash: partial' trace"*. **트레이스 라벨을 위한 강제 대입이며 런타임 상태가 아니다** |
| 6 | 같은 파일 `:641` | `return S_END;` — 리더는 스캔에서 **튜플을 한 건도 받지 않는다** |
| 7 | `src/query/query_executor.c:1243-1247` | 리더의 튜플 단위 해시 패스는 `qexec_end_one_iteration()` 안에만 있다. #6 때문에 이 경로는 실행되지 않는다 |
| 8 | `src/query/query_executor.c:27911` | 리더의 `agg_hash_context->state`는 `HS_ACCEPT_ALL`로 초기화된 뒤 **아무도 바꾸지 않는다** |
| 9 | `src/query/query_executor.c:4845` | `state = HS_REJECT_ALL`로의 **유일한** 전이(`context->tuple_count > 2000` ∧ `group_count/tuple_count > 0.5`)는 `qexec_hash_gby_agg_tuple()` 안에 있고, 이 경로에서는 **워커 클론**에만 적용된다. 상태 enum은 3값뿐이다(`src/storage/storage_common.h:1240-1245`: `HS_NONE`/`HS_ACCEPT_ALL`/`HS_REJECT_ALL`) |
| 10 | **`src/query/query_executor.c:5682`** (IMP-015) | `gby_px.hash_eligible = (gbstate.hash_eligible && gbstate.agg_hash_context->state != HS_REJECT_ALL)` → `(1 && HS_ACCEPT_ALL != HS_REJECT_ALL)` = **1**. base(`607f1ee9f`)의 `:5657`은 `gby_px.hash_eligible = gbstate.hash_eligible` = **1** |
| 11 | `src/storage/external_sort.c:1493` | `sort_param->px_parallel_num = sort_check_parallelism (…)` |
| 12 | **`src/storage/external_sort.c:5232`** | `if (px == NULL || px->hash_eligible) { return 1; }` ⇒ **직렬 확정** |

**원인 지점은 `external_sort.c:5232`이고, 그것을 발화시키는 입력은
`query_executor.c:5682`(IMP-015) / `:5657`(base)이며, 그 입력을 그렇게 만드는 근본은
`px_scan_result_handler.cpp:635`(라벨 강제) + `:641`(리더 해시 패스 부재)다.**

### 2-c. 직렬 스캔 경로에서는 왜 정상인가

직렬 스캔에서는 리더가 자기 해시 패스를 돌리므로 `query_executor.c:4862`
(`xasl->groupby_stats.groupby_hash = context->state`)에서 **라벨이 상태와 같아진다**.
Q15의 grouping(`l_suppkey`, SF10에서 distinct 100,000)은 입력 접두 2,000행에서 이미
`group_count/tuple_count ≈ 1.0 > 0.5`이므로 §2-b #9의 중단이 즉시 발화하여 `HS_REJECT_ALL`이 된다.
그러면 IMP-015의 `:5682`가 `hash_eligible = 0`을 만들어 `:5232`를 통과하고, 정렬은 병렬로 발동한다.
**즉 IMP-015의 변경 (a)는 직렬 스캔 경로에서는 설계대로 작동하고, 병렬 스캔 경로에서는 no-op이다.**

## 3. 재현 증거 — 힌트 대조쌍 (결정적)

같은 바이너리·같은 데이터·같은 SQL, **차이는 스캔 병렬성 힌트 하나**.
문장은 Q15 뷰 본문과 동일한 3개월 창(`queries/q15_create_view-cubrid.sql`)을 쓰고,
결과 행 폭주를 피하려 파생 테이블을 `count(*)`로 감쌌다(group-by 노드는 그대로 유지된다).
각 leg = uncounted 워밍업 1회 + `SET TRACE ON` 트레이스 1회.
프로브 스크립트: `work/BASELINE/q15-diagnosis/q15_diag_probe.sh`.

| leg | 힌트 | grouping | SCAN | GROUPBY 라벨 | group-by sort page | **병렬 발동** |
|---|---|---|---|---|---|---|
| **A** | (없음) | `l_suppkey` (Q15와 동일) | `parallel workers: 6, gather: mergeable list` | `hash: partial` | **19,926** | **없음 = 직렬** |
| **B** | `/*+ NO_PARALLEL_SCAN */` | `l_suppkey` (Q15와 동일) | 직렬 | `hash: partial` | 5,415 | **`parallel workers: 2`** |
| **C** | (없음) | `l_orderkey, l_linenumber` (유일키) | `parallel workers: 6, gather: mergeable list` | `hash: partial` | **32,247** | **없음 = 직렬** |
| **D** | `/*+ NO_PARALLEL_SCAN */` | `l_orderkey, l_linenumber` (유일키) | 직렬 | `hash: partial` | 7,854 | **`parallel workers: 3`** |

원자료: `legA-trace.out` … `legD-trace.out`, 요약 `legs-summary.txt`, wall `legs.wall`.

**A vs B** 는 Q15 자신의 grouping에 대한 대조쌍이고, **C vs D** 는 다른 grouping 형태로 같은 결론을
재현한다. 네 leg 모두 트레이스 라벨은 `hash: partial`로 **동일**한데 발동 결과는 정반대다 ⇒
`hash: partial`은 병렬 스캔 경로에서 런타임 상태를 뜻하지 않는다(§2-b #5). 그리고 병렬 스캔을 끄면
같은 문장이 병렬로 발동한다 ⇒ 차이를 만드는 유일한 변수는 **리더의 `agg_hash_context->state`**이며,
그것을 읽는 지점은 `query_executor.c:5682` 하나, 그 값이 소비되는 지점은 `external_sort.c:5232`
하나다.

### 3-a. 그 병렬 서브라인이 **메인** group-by 정렬임을 확정한다

트레이스만으로는 두 정렬을 구분할 수 없다 — `gby_px.stats`와 `part_px.stats`가 모두 같은
`&xasl->groupby_stats`를 가리키기 때문이다(IMP-015 `query_executor.c:5591`, `:5683`; D1이 지적한
그 모호성). 따라서 leg B/D의 `parallel workers` 서브라인이 메인 정렬인지 부분 해시리스트 정렬인지를
따로 확정해야 한다. 두 갈래 근거가 모두 메인 정렬을 지목한다.

**(1) 정렬 작업량이 일치한다.** 워커 page 합이 대조 leg의 직렬 총량과 사실상 같다:

| 대조쌍 | 직렬 leg 총 page | 병렬 leg 워커 page 합 | 일치 |
|---|---|---|---|
| A ↔ B | **19,926** (leg A) | 2 × 9,150..11,261 = **18,300..22,522** (leg B) | 19,926 ∈ 구간 ✔ |
| C ↔ D | **32,247** (leg C) | 3 × 9,710..11,588 = **29,130..34,764** (leg D) | 32,247 ∈ 구간 ✔ |

즉 병렬 leg의 워커들이 처리한 정렬 규모는 직렬 leg가 혼자 처리한 그 2,265,714행 정렬과 동일하다.
동시에 **리더 쪽** page/ioread는 붕괴한다(leg A 19,926/6,076 → leg B 5,415/**15**;
leg C 32,247/24,659 → leg D 7,854/**718**) — IMP-015 report가 Q10에서 criterion-4 signature
(ii) sort-worker ioread ~0, (iii) GROUPBY ioread 급감으로 인용한 것과 같은 지문이다.

**(2) 부분 해시리스트 정렬은 이 leg들에서 병렬일 수 없다.** 직렬 스캔 leg에서 리더 해시는
`query_executor.c:4839`의 `tuple_count > 2000` 조건이 처음 성립하는 지점, 즉 입력 약 2,001행에서
중단된다(leg B는 l_suppkey distinct 100,000이라 그 접두에서 selectivity ≈ 0.99, leg D는 유일키라
1.0 — 둘 다 `> 0.5`). 중단 시 `qdata_save_agg_htable_to_list`가 덤프하는 `part_list_id`는 그 시점의
해시 엔트리 약 2,000건뿐이고, 중단 이후에는 `query_executor.c:1244`가 `state != HS_REJECT_ALL`을
요구하므로 **더 이상 아무 튜플도 부분리스트로 가지 않는다**. 따라서 `part_list_id->page_cnt`는
16KB 페이지 기준 십여 page 규모로, `compute_parallel_degree`의 `sort_page_threshold`(2048)에
한참 미달한다(`px_parallel.cpp:117-120`) ⇒ 부분리스트 정렬은 **직렬**로 돈다. 9,150–11,588 page를
처리한 워커들이 그 정렬일 수는 없다.

두 근거로, leg B/D에서 병렬화된 것은 **메인 group-by 폴백 정렬**이다.

### Q15 본체 재확인

`create view` → `select` → `drop view` 한 세션(§3-c: Q15는 하나의 논리 단위), traced wall 11.04 s:

```
SCAN (table: dba.lineitem) … (parallel workers: 6, … gather: mergeable list)
GROUPBY (time: 2610, hash: partial, sort: true, page: 17384, ioread: 13926, rows: 100000)
SCAN (table: dba.lineitem) … (parallel workers: 6, … gather: mergeable list)
GROUPBY (time: 2638, hash: partial, sort: true, page: 14888, ioread: 17698, rows: 100000)
```

두 GROUPBY 모두 `parallel workers` 서브라인 없음 = 직렬. §6-b 객체 정리: 실행 전 `db_class` count 0,
실행 후 0(drop 완료) — `view-before.out` / `view-after.out`.

## 4. 배제된 후보 (D1이 남긴 셋 전부)

`sort_check_parallelism()`의 `SORT_GROUP_BY` 분기는 `external_sort.c:5228-5247`이고,
`:5232`의 `return 1`은 그 아래 모든 로직보다 **앞에** 있다. 따라서:

| D1 잔여 후보 | 위치 | 배제 근거 |
|---|---|---|
| `input_list->page_cnt` 문턱(2048) 미달 | `:5237-5239` → `px_parallel.cpp:117-120` | **`:5232`에서 이미 반환되어 도달하지 않는다.** 정량 반증도 있다: §3-a에 따라 leg C(직렬)의 정렬 총량 **32,247 page**와 leg D(병렬)의 워커 합 **29,130..34,764 page**는 사실상 **같은 규모**인데 발동 결과는 정반대다. 크기가 같고 결과가 갈리므로 크기는 원인이 아니다. leg A(19,926, 직렬) ↔ leg B(18,300..22,522, 병렬)도 동일. D1이 12개월 창 85,534 page로 확대해도 직렬이었던 것과 정합 |
| `px->parallelism`(=`xasl->parallelism`) 힌트가 0 또는 1 | `:5238-5239` → `px_parallel.cpp:122-141` | **`:5232` 하류**라 도달하지 않는다. 추가로 `PARALLEL` 힌트 없는 질의는 `xasl_generation.c:17218`/`:17594`에서 `xasl->parallelism = -1`(auto-compute)이며, leg B/D가 **같은 XASL 형태로 병렬 발동**했으므로 힌트가 0·1일 수 없다 |
| `input_list->tuple_cnt < parallel_num` 등 | `:5240` | 동일하게 `:5232` 하류. leg A/C의 tuple_cnt는 2,265,714 |
| `try_reserve_workers` 실패 | `:5244` | 동일하게 `:5232` 하류. 같은 서버·같은 시각에 SCAN이 6워커, leg B/D의 정렬이 2·3워커를 확보했으므로 풀 고갈도 아니다 |
| 다른 `sort_listfile` 호출점 | — | Q15 group-by는 `query_executor.c:5686`(IMP-015) / `:5661`(base) 한 곳이다. `list_id = xasl->list_id`(`:5355`) |
| `px == NULL` | `:5232` 전반부 | 아니다 — `gby_px`는 `:5679-5684`에서 항상 구성되어 전달된다 |
| buildlist vs buildvalue 등 XASL 형태 차이 | — | `qexec_groupby()`는 `xasl->proc.buildlist` 전용이고 `query_executor.c:1243`도 `xasl->type == BUILDLIST_PROC`를 요구한다. 네 leg 모두 같은 BUILDLIST 형태이며 결과만 갈린다 |
| 해시 상태 | — | 배제되지 **않았다** — D1은 `hash: partial`을 `HS_REJECT_ALL`로 읽어 "첫 게이트 통과"로 판단했지만, 병렬 스캔 경로에서 그 라벨은 강제값이고 게이트가 읽는 리더 상태는 `HS_ACCEPT_ALL`이다. **이것이 바로 원인이다** |

D1의 "힌트 후보는 Q18 관측과 상충한다"는 관찰은 옳았고, 그 상충의 진짜 설명이 §2다:
Q18에서 병렬로 돌던 정렬은 IMP-015가 `part_px.hash_eligible = 0`으로 **무조건** 적격화한 부분
해시리스트 정렬(`worktrees/IMP-015` `query_executor.c:5587-5592`)이고, 메인 group-by 정렬은
`:5682`가 1을 만들어 직렬이었다. 두 호출점은 같은 문장·같은 `xasl->parallelism`·같은 워커 풀을
공유하므로, 갈린 변수는 `hash_eligible` 하나뿐이라는 점이 소스로 확정된다.

## 5. 기존 후보와의 관계

### IMP-015 (group-by 폴백 정렬 병렬화 — 이번 진단의 직접 대상)

- **가설의 절반이 병렬 스캔 경로에서 성립하지 않는다.** IMP-015 `implementation-plan.md` §5-c 항목 1은
  "직렬 원인은 오로지 플랜타임 `hash_eligible` 플래그이고, 호출점별 런타임 진실로 치환하면 병렬화된다"였다.
  치환된 런타임 진실이 **리더의** `agg_hash_context->state`인데, 병렬 스캔 mergeable-list gather에서는
  리더가 해시 패스를 돌지 않아 그 값이 영원히 `HS_ACCEPT_ALL`이다. 그 경로에서 변경 (a)는 **no-op**이다.
- **Q10 게이트 결과는 무효화되지 않는다.** IMP-015 report의 Q10 arming 증거
  (`GROUPBY … (parallel workers: 4, …)`, sort page 50,280, ioread 4..12)는 리더가 자기 해시 패스를
  돌고 `HS_REJECT_ALL`로 중단한 경로에서 얻어진 것이며, leg B/D가 같은 메커니즘을 독립 재현한다.
  IMP-015의 검증된 적용 범위는 **"리더가 해시 패스를 수행하는 group-by"**로 좁혀진다.
- **§5-c 항목 7의 "Q15 (armed, lower-bound corroboration)"는 선정 오류였다.** Q15는 armed가 아니었고,
  armed로 보이게 만든 관측치(`hash: partial`)가 강제 라벨이었다. 이는 IMP-015 verdict의 결함이 아니라
  **corroboration 타깃 선정의 결함**이다 — 게이트는 Q10이었다.
- Phase 1B 반영: IMP-015의 benefit은 **병렬 스캔 mergeable-list gather로 입력을 받는 group-by를
  대상 집합에서 제외**하고 재검토해야 한다. 이 캠페인 워크로드에서 그 경로는 드물지 않다 —
  Q15(2노드)·Q18이 모두 해당한다.

### IMP-032 (구 IC-5, ② merge / ③ finalize drain 병렬화 — `stopped`)

- D1의 `UNPROVABLE_ON_THIS_HOST` 판정은 **강화된다.** Q15에서 ②·③가 0표본인 이유가
  "표적 국면이 존재하지 않는다"에서 "표적 국면이 `:5232`에서 차단되어 진입 자체가 불가능하다"로
  **기전까지 확정**되었다. 기대효과 0.00% < MDE 하한 1%는 그대로다.
- IMP-032의 표적을 Q15에서 성립시키려면 **먼저 이 진단의 원인을 해소해야 한다** — 즉 IMP-032는
  §6의 신규 후보에 대한 **의존(predecessor) 관계**를 갖는다. 순서를 바꿀 수 없다.

### IMP-016 (해시 집계 대안 경로)

- 직접 충돌은 없다. 다만 §2-c에서 드러난 `qexec_hash_gby_agg_tuple()`의 **접두 기반 선택도 판정**
  (`query_executor.c:4838-4855`: 앞 2,000행에서 `group_count/tuple_count > 0.5`면 즉시 해시 포기)이
  Q15처럼 distinct 100,000인 grouping을 사실상 항상 해시에서 탈락시킨다는 사실은 IMP-016의 근거를
  보강한다. IMP-015 ⟂ IMP-016(alternative cluster)는 유지된다 — 이번 진단은 alternative 관계를
  바꾸지 않고, IMP-015 쪽 적용 범위만 좁힌다.

### IMP-021 (해당 정렬 자체를 제거)

- **anti-additive 관계가 강화된다.** IMP-021이 이 group-by 정렬 워크로드를 없애면 IMP-015·IMP-032·
  §6 신규 후보의 표적이 동시에 사라진다. `feasibility-assessment.json`의
  **IMP-021 ⊃ IMP-015, IMP-023** containment는 그대로 유효하고, 순서 결정의 중요도가 올라간다.

### IMP-023 (post-sort consumer loop)

- 무관하다. 정렬 **이후** 소비 루프이며 `:5232` 상류가 아니다. 관계 변화 없음.

### IMP-017

- 무관하다(관측 정확도 lane). 단, §6 신규 후보가 **트레이스 라벨이 런타임 상태를 오표기한다**는
  측정-정확성 결함을 포함하므로, 그 부분은 IMP-017과 같은
  `Diagnostic-Measurement-correctness` lane 성격을 갖는다.

## 6. ID 미할당 신규 후보 (사용자 결정 항목)

§1-b에 따라 **새 IMP ID를 할당하지 않았다**(`next_id`는 `IMP-032`로 소진). 아래를 Phase 1B 랭킹
보고서의 "ID 미할당 신규 후보"로 올려 사용자 결정을 받는다.

> **NEW-CAND-A (ID 미할당) — 병렬 스캔 gather 경로에서 group-by 폴백 정렬의 병렬 적격성 판정**
>
> - **문제**: `px_scan_result_handler.cpp:635`가 트레이스 라벨용으로만 `HS_REJECT_ALL`을 강제하고,
>   리더의 `agg_hash_context->state`는 `HS_ACCEPT_ALL`로 남아
>   `query_executor.c:5682` → `external_sort.c:5232`가 병렬 정렬을 무조건 차단한다.
> - **두 갈래 성격** (분리 여부는 사용자 결정):
>   (i) *성능* — 병렬 스캔 gather 경로에서도 폴백 정렬이 병렬화되도록 적격성 판정을 호출점 진실로
>   바꾸는 것. IMP-015 변경 (b)(`part_px.hash_eligible = 0` 무조건)의 논리가 그대로 적용된다:
>   이 정렬이 도는 시점에 해시 패스는 이미 끝났으므로 "살아있는 해시 패스가 이 정렬을 작게 만들 수
>   있다"는 전제가 성립하지 않는다.
>   (ii) *측정 정확성* — 강제 라벨과 런타임 상태의 분리. 현재 트레이스는 리더가 해시를 돌았는지
>   여부를 구분할 수 없어, 이 캠페인에서 실제로 후보 선정 오류(IMP-015 §5-c 항목 7)를 유발했다.
> - **관계**: IMP-032의 predecessor(표적 국면 진입 선행 조건). IMP-015와는 상보 관계(같은 게이트의
>   서로 다른 입력 경로). IMP-021과는 anti-additive.
> - **표적 질의**: Q15(2노드), Q18. 추가 스윕 필요 — Phase 1A 완료 후 `mergeable list` gather +
>   group-by 조합 질의를 전수 식별해야 정확한 대상 집합이 나온다.
> - **미확정**: 기대효과. 이번 작업은 읽기 전용 진단이며 §6-c A/B를 수행하지 않았다. leg A↔B,
>   C↔D의 wall 차이는 스캔 병렬성까지 함께 바뀐 값이므로 **정렬 병렬화의 효과로 환산할 수 없다.**
>   Phase 2 개시 금지 규율에 따라 여기서 정지한다.

## 7. 원자료 색인

주장 → 원자료 → 근거형 → SHA-256(앞 16). 원자료 루트:
`/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/BASELINE/q15-diagnosis/`

| 주장 | 원자료 | 근거형 | sha256(16) |
|---|---|---|---|
| 프로브 정의·힌트 대조쌍 설계 | `q15_diag_probe.sh` | 절차 | `940c0cf3194e6aeb` |
| leg A 병렬스캔 → group-by 직렬 | `legA-trace.out` | 트레이스 | `f69914bd7005ce16` |
| leg B 직렬스캔 → group-by 병렬 2워커 | `legB-trace.out` | 트레이스 | `c7ce542b3a4ae86e` |
| leg C 병렬스캔·sort page 32,247 → 직렬 | `legC-trace.out` | 트레이스 | `fe0758196bb44cd4` |
| leg D 직렬스캔 → group-by 병렬 3워커 | `legD-trace.out` | 트레이스 | `7985f30a3716d751` |
| Q15 본체 2노드 직렬 + view 부재·삭제 증명 | `q15-trace.out` | 트레이스 | `7efd2f2fc1085590` |
| 4 leg 요약표 | `legs-summary.txt` | 파생 | `6540a08682ff7ec8` |
| Q15 본체 요약 + wall | `q15full-summary.txt` | 파생 | `ee37998134601322` |
| 바이너리·conf·핀 지문 | `preflight.txt` | 계약 | `f330e14d870ac35e` |
| §3-b ownership + all-TID affinity | `identity-after-start.json` | 게이트 | `6b85a9fedf76654d` |
| 잔존 `cub_master` 정지 근거 | `master-cleanup.txt` | 게이트 | `fc567a21ea55ff98` |
| bgload 기록(차단 미적용) | `bgload-start.json` / `bgload-end.json` | 환경 | `1aea8733d848d0c7` / `c3753e52ac05b6a2` |
| 자식 tmux 드라이버 신원(§8-b) | `driver-record.json` | 계약 | `7f954445c2ae61ac` |
| 전체 지문 목록 | `fingerprints.txt` | 색인 | — |

소스 인용은 전부 위 §0의 두 커밋(`607f1ee9f` / `61f4b4cf9`)에서 직접 읽었다.

## §8-c 상태 블록

```yaml
TPCH_SSPQ_IMPL_STATUS:
  campaign_id: tpch-sspq-impl-r1-20260803
  imp_id: BASELINE
  impl_ssot_commit: eccdd1ae58cd733ed3121585146d68b9ae54a73f
  impl_ssot_blob_sha: 15b42ddca521444fa54b34b0fa8477ed2df643f6
  session_id: 019fcafc-dc0b-7000-a833-0f5f2692b289
  stage: task2-q15-parallel-non-arming-diagnosis-complete
  state: complete
  branch: null
  report_commit: pending-commit
  verdict: null
  artifact_fingerprint: legA=f69914bd7005ce16, legB=c7ce542b3a4ae86e, legC=fe0758196bb44cd4, legD=7985f30a3716d751
  timestamp: 2026-08-04T04:43:03Z
  next_action: handoff 작업 3 — Phase 1A fast 스윕 → restart-variance 보정 → Phase 1B 랭킹
  source_modified: none (읽기 전용; base-src / worktrees/IMP-015 미변경)
```
