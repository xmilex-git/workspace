# IMP-032 (구 IC-5) — report: **rejected**

> **한 줄 요약**: IMP-015는 구현되어 그대로 서 있고(accepted, provisional), 그 위에 얹으려 한 후속
> 후보 IMP-032는 **착수 전 검증 단계에서 기각**됐다. 소스 한 줄도 바꾸지 않았고 A/B 예산도 쓰지 않았다.

## 1. Identity, 핀, diff

| 항목 | 값 |
|---|---|
| IMP ID | `IMP-032` (구 개선 후보 레지스트리 `IC-5` / ⑤ — GROUP BY 리더 merge/finalize 병렬화) |
| lane | performance |
| 캠페인 | `tpch-sspq-impl-r1-20260803` |
| IMPL-SSOT | commit `276d8e866f0f4702648ccb9b8c00c8c5410931e9`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` |
| 확정 스펙 | `tpch-sspq/impl/IC-5-implementation-spec.md`, blob `580cd4f5f17ab47b3418352d1aed18689aa9e258` |
| CUBRID base SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (동결) |
| 브랜치 | `impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize` |
| 분기점 | `61f4b4cf967dbc2f0cd18422b83561ef44366382` (IMP-015 patch commit — spec D2 스태킹, 사용자 승인) |
| 패치 커밋 | **없음** (브랜치 자체 커밋 0개) |
| diffstat | **없음** — 소스 수정 0 파일 / 0 라인 |

§1-d 핀 검증은 7단계 전수 통과했다(branch main, `tpch-sspq` clean, ff-only pull, local=remote=origin/main
일치, blob 대조, 전문 정독). 근거: `work/IMP-032/status/G001-pin-and-worktree.md`.

## 2. 실제 변경 LOC·파일과 150% 검사

| 항목 | 값 |
|---|---|
| 계획 밴드 (spec §B 항목 4) | low 50 / likely 140 / high 280 |
| §5-d 하드스톱 | 420 (= high × 150%) |
| **실제 변경** | **0 파일 / 0 라인** |
| 150% 검사 | 해당 없음 (변경 없음) |

단, §5-d 하드스톱은 **다른 축에서 발동했다**: A3 반증(§4) 해소에 필요한 기계장치가 **XASL 직렬화 /
XASL 캐시 서브시스템**을 접촉하며, 항목별 재산정 LOC은 **390–600**으로 420을 넘는다.

| 재산정 항목 | 추정 LOC |
|---|---|
| 워커별 XASL 복제 + 워커별 `xasl_state`/`VAL_DESCR` + 해제 | 120–160 |
| 복제본에서 BUILDLIST 노드 확인 후 워커별 `GROUPBY_STATE` 구성/해제 + 출력 리스트 | 80–140 |
| drain 그룹 경계 skip/overrun + 전체 페이지수 plumbing (`SORT_PARAM`, `sort_split_last_run`) | 60–100 |
| `sort_put_result_for_parallel` SORT_GROUP_BY 분기 + ORDER_BY 골격 합류 + coda | 50–80 |
| 직렬 폴백 게이트 5종 + `SORT_LISTFILE_PX_ARG` 필드 + 두 호출부 | 40–60 |
| A6 finalize px 통계 + `query_dump.c` 방출 + 워커 통계 합산 | 40–60 |
| **합계** | **390–600** |

대조군: px_scan의 복제 배관만 떼어도 `clone_xasl` 75줄(`px_scan_task.cpp:569-643`) + 해제 24줄(`:495-518`)
+ vd 복제 23줄(`px_scan.cpp:1642-1664`) = 약 122줄이고, 이는 이미 task/manager 프레임워크가 존재하는
곳에서 `xcache`/`stx_map_stream_to_xasl`을 **재사용**한 수치다. 정렬 drain 문맥에는 그 프레임워크가 없다.

## 3. 정합성 (§6-b 5개 필수 검사)

전부 **미수행 — 대상 없음**. P 바이너리가 존재하지 않으므로 before/after 비교 대상이 없다.

| # | 검사 | 처분 |
|---|---|---|
| 1 | 변경 경로를 타는 단위/회귀 TC | N/A — 변경 경로 없음 |
| 2 | 타깃 질의 | N/A |
| 3 | `q_relations` 전 질의 | N/A |
| 4 | Q01–Q22 결과 스모크 | N/A |
| 5 | 동시성/메모리 후보용 스트레스 + 진단 빌드 | N/A (D6 게이트 미도달) |

정합성 실패는 **없었다**(실패할 코드가 없다). D1 프로브 중 Q15 view는 실행 전 부재 증명 0건,
실행 후 drop 확인 0건으로 §6-b의 Q15 객체 정리 조항만 부수적으로 만족했다.

## 4. 기각 근거 ① — spec §A **A3 반증** (stop-and-report)

`GROUPBY_STATE`의 워커별 복제가 spec 선언 반경(`external_sort.c`, `query_executor.c`, 헤더 소폭)
안에서 불가능하다. 상세: `A1-A8-source-verification.md`.

- **공유 `g_val_list`/`g_regu_list` 인스턴스** — `qexec_gby_agg_tuple`이 튜플마다
  `fetch_val_list`로 XASL 소유 DB_VALUE에 쓰고(`query_executor.c:4587`)
  `qdata_evaluate_aggregate_list`가 같은 값을 읽는다(`:4597`). A3가 반증 예시로 명시한 항목 그 자체.
- **`g_output_agg_list`** — finalize가 XASL 소유 DB_VALUE에 결과를 옮긴다(`:19947-19948`); 이 값이
  outptr/having regu 트리의 바인딩 지점이다.
- **`having_pred`/`g_outptr_list`/공유 `xasl_state->vd`** (`:19973`, `:20047-20048`, `:20081`).
- **`agg_hash_context` 부분리스트 단일 순차 커서** (`:5191-5228`, `:5250-5309`) — XASL을 복제해도
  복제본 컨텍스트는 비어 있어 리더의 spill 산출물을 대신하지 못한다.
- `grbynum_val` + `SORT_PUT_STOP` 단발 발화, 비원자적 `groupby_stats.rows++`, `composite_lock`.

**ORDER_BY 미러링(spec D4의 설계 전제)이 성립하지 않는다**: `qexec_ordby_put_next`
(`query_executor.c:3772-3900`)는 순수 튜플 복사이고 XASL 표현식 평가가 없다. 게다가 결정이 이미
소스에 적혀 있다 — `external_sort.c:5720-5722`:
*"put_fn must not run in parallel because ordbynum_val state is shared and SORT_PUT_STOP must fire
exactly once at the global LIMIT boundary."* `ordbynum_val` **하나** 때문에 ORDER_WITH_LIMIT도 직렬
drain을 택한다. GROUP_BY의 put_fn은 그보다 훨씬 큰 공유 상태를 갖는다.

A1/A2/A4/A5/A6/A8은 holds, A7은 A4 게이트 전제 하 조건부 holds였다. 즉 **A3 하나가 설계를 무효화했다.**

## 5. 기각 근거 ② — spec D1 `UNPROVABLE_ON_THIS_HOST` (Q15 게이트)

D1 귀속 프로브(보존 `install/IMP-015` 바이너리, 재빌드 없음, quiet-gate 차단 미적용·bgload 기록만,
`-F 99` DWARF 콜체인). 상세: `D1-attribution-probe.md`.

| | Q15 (1차 게이트) | Q18 (관측) |
|---|---|---|
| GROUPBY 해시 상태 | `hash: partial` (= HS_REJECT_ALL) | `hash: partial` |
| ③ `sort_put_result_from_tmpfile` 표본 | **0** / 5,088 | 716 / 10,684 (≈ 7.2 s) |
| ② `sort_merge_nruns` 표본 | **0** | 103 (≈ 1.0 s) |
| `sort_end_parallelism` / `sort_listfile_execute` | **0 / absent** | 716 / 3.72% |
| 메인 group-by 폴백 정렬 | **직렬** | **직렬** (`sort_exphase_merge` 1,700 아래 `qexec_gby_put_next` 1,203) |
| 병렬화된 정렬 | 없음 | 해시 **부분리스트** 정렬뿐 (③ 716 중 688이 `qexec_hash_gby_put_next`와 동시 출현, `qexec_gby_put_next`와는 **0**) |

- **Q15 기대효과 = 0.00%**: 표적 국면 ②/③이 실행되지 않으므로 "측정된 리더 잔여 × Amdahl 분율"이
  어떤 분율에서도 0이다. §6-d의 MDE 하한이 `max(1%, 2×CV)`이므로 대체 MDE의 정확한 값과 무관하게
  `0.00% < 1%` ⇒ `UNPROVABLE_ON_THIS_HOST`.
- 원인 절단: 뷰 본문 단독 실행도 직렬, 12개월 창(9,123,688행 / sort page 85,534)에서도 직렬
  ⇒ 크기 문턱(2048)·상위 질의 구조·해시 상태 모두 원인이 아니다.
- 부수 확인: 그 유일한 병렬 인스턴스 내부에서는 **③ : ② = 87.4 : 12.6** — spec D4의 "③ 지배" 가정
  자체는 참이다. 즉 가설의 *방향*은 맞았고 *적용 지점*이 존재하지 않았다.

## 6. Before/after 타이밍

**없음.** P 바이너리 미존재로 §6-c의 `B → P → P → B` 블록을 한 번도 실행하지 않았다(예산 미소모).
아래는 A/B가 아니라 **귀속 프로브** 수치이며 성능 비교로 인용해서는 안 된다:

| 프로브 런 | wall |
|---|---|
| Q18 traced (LBR) | 37.94 s |
| Q18 dwarf 재기록 | 37.52 s |
| Q15 traced (LBR) | 10.88 s |
| Q15 dwarf 재기록 | 10.94 s |

## 7. Paired 통계

**없음.** paired block-median 비율, bootstrap 95% CI, pair count 모두 미산출. MDE는 Q15에 대해
§6-d-1 corrected MDE가 **존재하지 않으며**(`restart-variance-calibration.json`의
`queries_not_covered_at_all`에 Q15 포함, Phase 1A 미실행), 판정에는 §6-d의 하한 1%만 사용했다.

## 8. 플랜/작업량 안정성

플랜 모양 변경 없음(변경 코드 없음). `A/B_CONFOUNDED_PLAN_CHANGE` 해당 없음.

## 9. CPU·TWU·프로파일

TWU/serial_tail의 공식 텔레메트리 비교는 spec §C에 따라 cumulative-phase로 이월된 항목이고, 이
IMP에서는 프로브 수준 귀속 증거로 대체했다(§5의 표). 프로파일에서 움직인 밴드는 없다(처치 없음).
프로브가 관측한 프로파일 분포(Q18, 전 서버 cycles 포괄): `qexec_hash_gby_agg_tuple` 39.39%,
`sort_listfile` 21.02%, `sort_exphase_merge` 16.87%, `qexec_gby_put_next` 11.98%,
`sort_end_parallelism` = `sort_put_result_from_tmpfile` 7.21%, `qexec_hash_gby_put_next` 6.95%.

## 10. 기대 대비 측정 (§7-e)

spec §B 항목 1의 가설은 "IMP-015 이후 잔여 병목은 리더 직렬 국면(②+③)이며 ③을 그룹 경계 정렬 분할로
병렬화하면 Q15 wall이 줄어든다"였다. 측정은 이를 **부분적으로 지지하고 결정적으로 반증한다**:

- 지지: 병렬 폴백 정렬이 실제로 발동하는 인스턴스에서는 리더 잔여가 지배적이고 그 안에서 ③이 ②를
  87.4:12.6으로 압도한다.
- 반증: **Q15에서는 병렬 폴백 정렬 자체가 발동하지 않는다.** 따라서 "IMP-015 이후의 잔여"라는 전제가
  Q15에 대해 거짓이다. §7-e가 요구하는 근본원인 재검토 결과, 원래 증거 귀속(카드의 69.8%/50.1% 밴드,
  구 측정 레짐)이 Q15에 대해 **잘못된 지점을 지목**했음이 확인된다 — AMEND-F가 경고한 "프로파일 밴드는
  자동으로 제거가능 효과가 아니다"의 실례다.

## 11. 회귀

측정 없음(처치 없음). 비타깃 질의 회귀 0건 — 코드 변경이 없으므로 회귀가 발생할 수 없다.
Q10 비대칭 가드(IMP-015가 확보한 −9.92%)는 이 IMP로 인해 위협받지 않는다.

## 12. Verdict

**`rejected`** — 결정: 사용자 지시 (2026-08-04, authority order 1), §11-a 에스컬레이션에 대한 응답.

결정 근거의 형식적 위치를 정확히 기록한다:

- **§7-a(accepted)는 만족 불가**: 기준 3(point improvement ≥ MDE)은 Q15 기대효과 0%로 원리적으로
  불가능하고, 기준 4(기대 metric signature가 예측 방향으로 이동)도 신호가 발생할 국면이 실행되지
  않으므로 불가능하다.
- **§7-c(rejected)의 측정 기준은 행사되지 않았다** — P 바이너리가 없어 정합성 실패도, 성능 열화도,
  신호 부동도 *측정*된 바 없다. 가장 가까운 형식 대응은 "기대 metric signature가 이동하지 않음"이지만,
  실제 사유는 측정 실패가 아니라 **표적 부재 + 설계 불가**다.
- 따라서 이 verdict는 §7의 측정 판정이 아니라 **§11-a 정지-보고에 대한 사용자 결정**이며, 그 근거는
  §4(A3 반증)와 §5(`UNPROVABLE_ON_THIS_HOST`)다. `inconclusive`(§7-b: 12 pair 후에도 CI가 1.0 포함)가
  아닌 이유는 pair를 수집한 적이 없고 수집해도 효과가 0으로 논증되기 때문이다.

기각 시점의 보존 상태: 브랜치 `impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize`는
`61f4b4cf9`에 그대로 남아 있다(§7-b의 브랜치 보존 관행 준용). worktree도 clean 상태로 보존한다.

## 13. Raw 증거 색인

형식: `claim → raw file:line → formula → evidence type → SHA-256`

| claim | raw | formula/method | type | sha256 (앞 16) |
|---|---|---|---|---|
| Q15 group-by 폴백 정렬이 직렬 | `work/IMP-032/probe/q15-trace.out` (GROUPBY 라인에 `parallel workers` 부재) | SET TRACE ON 1회 | trace | `2d772f05247d1f5c` |
| Q15 ③/② 표본 0 | `work/IMP-032/probe/q15.chaincounts.txt` | `perf script` 표본별 콜체인 심볼 동시출현 계수 | perf-derived | 매니페스트 참조 |
| Q15 병렬 심볼 absent | `work/IMP-032/probe/q15.phase-attrib.txt` | `perf report -g none --children --sort symbol` | perf-derived | 매니페스트 참조 |
| Q18 ③ 716 / ② 103, ③∧hash_gby 688 / ③∧gby 0 | `work/IMP-032/probe/q18.chaincounts.txt` | 동일 계수법 | perf-derived | 매니페스트 참조 |
| Q18 병렬 발동 + 워커 6 | `work/IMP-032/probe/q18-trace.out` | SET TRACE ON 1회 | trace | `dfe4af21f99d2d55` |
| 크기 원인 배제 (12개월 창도 직렬) | `work/IMP-032/probe/q15diag.out` | 행수 2,265,714 / 9,123,688 + 트레이스 | trace | `3276d40f03a1feef` |
| 상위 구조 원인 배제 (뷰 본문 단독) | `work/IMP-032/probe/q15body-trace.out` | 트레이스 | trace | `39a33fe1278366b8` |
| 원 perf 표본 | `work/IMP-032/probe/q{15,18}.dwarf.perf.data` | `perf record -F 99 --call-graph dwarf,2048 -p <cub_server>` | perf-sample | `81de5d817755b568` / `3a7699a3bcf4467e` |
| A3 반증 소스 근거 | `worktrees/IMP-032/src/query/query_executor.c:4587,4597,19947-19948,19973,20047-20048,20081` + `src/storage/external_sort.c:5720-5722` | 핀 소스 판독 | source | 브랜치 `61f4b4cf9` |
| 프로브 계약 준수 | `work/IMP-032/probe/{preflight.txt,identity-*.json,bgload-*.json,master-cleanup.txt}` | conf sha256 / all-TID affinity / §3-b ownership | verification | 매니페스트 참조 |
| 전 산출물 지문 | `tpch-sspq/impl/IMP-032/raw-manifest.json` | 38개 산출물 개별 sha256 | manifest | 커밋 내 |

## 14. 브랜치·커밋·빌드 ID

| 항목 | 값 |
|---|---|
| 브랜치 | `impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize` (자체 커밋 0) |
| **B** (spec D3: 캠페인 base가 아니라 IMP-015 보존본) | `install/IMP-015/bin/cub_server` sha256 `0a376e0606f7395822cf0f4925b8290326b4f1131e6c865e5e7b291722726f30`, ELF Build ID `379ab8c0760ec526fbeee8b80f0a2da0d81759bd`, 재빌드 없음 |
| **P** | **없음** |
| runtime conf | `ad19f5ac1e7e983e4a0b1c113d21e25e096d02d3160445f9d10a2e8b6d9cb9ff` (§6-a-2 핀 일치, 프로브 블록에서 검증) |

## 14-a. 종료 검증 코호트 (기각 기록 자체에 대한 검증)

기각은 "측정하지 않았다"가 아니라 "측정해서 표적이 없음을 확인했다"이므로, 그 기록 자체를 동결하고
검증했다. 동결 스냅샷의 `sourceHash`와 경로별 sha256은 `closeout/verify-report.json`이 보유한다(이 문서에
해시를 적으면 자기참조가 되므로 여기에는 적지 않는다). generation 2 = 아래 cleaner 수정 2건 + red-team
정밀도 수정 1건 반영 후 재동결.

| lane | 결과 |
|---|---|
| cleaner (ai-slop-cleaner) | BLOCKING 2건 → 리더가 수정. `raw-manifest.json`의 죽은 필드 `verdict_absent_reason` 제거, `ab_evidence_absent_reason`/`phase`의 결정 이전 시제 표현 정정. advisory 3건은 보고서에만 기록. 리포트: `closeout/ai-slop-cleanup-report.md` |
| 기계 검증 | `closeout/verify_closeout.py` **15/15 통과**. 초기 실행에서 2개 체크가 실제로 실패해(문자열 오매칭, `pgrep` 자기매칭) 수정한 이력이 있다 — 하네스가 실패를 가리지 않는다는 증거다 |
| architect (read-only) | architecture/product/code = WATCH/WATCH/WATCH, recommendation COMMENT. 프레임 파일 자체의 결함은 없고, 유일한 blocker는 **Notion append가 아직 실행되지 않았다**는 것(§15 참조) |
| executor QA / red-team | **passed, 반증 0건.** 독립 파서(`closeout/redteam/recount.py`)로 Q15 5,088/0/0과 Q18 10,684/716/103/1,203/1,700/688/0을 전부 재도출해 일치 확인. `nm`/`objdump`로 `sort_run_final_single`·`sort_merge_worker_runs_to_one`이 인라인되어 심볼이 사라질 수 있음을 확인하고, 그래도 `sort_end_parallelism`·`sort_listfile_execute`·`qfile_sort_get_next_parallel`·트레이스 `parallel workers` 서브라인이라는 **인라인 무관 신호**로 Q15 직렬 판정이 유지됨을 검증. `grep`으로 반경 내 대체 복제 기계장치를 탐색해 부재 확인(A3 반증 유지). 리포트: `closeout/redteam/redteam-report.json` |

red-team이 지적한 정밀도 수정 1건을 반영했다: D1 보고서 Q15 표의 `sort_listfile` 480은 **부분문자열**
계수여서 파생 심볼(`sort_listfile_internal`/`_execute`)까지 포함하며 정확 토큰 계수는 459다. 판정에 사용한
심볼들은 다른 심볼의 접두사가 아니어서 두 방법이 일치한다 — 해당 caveat을 D1 보고서에 명기했다.

## 15. Notion 동기화 상태

이 호스트에 Notion 커넥터/`ntn` CLI가 없다(§10-c: 원격 워커는 Notion 쓰기를 수행하지 않는다).
따라서 §10-f에 따라 **완전한 payload를 담은 백필 레코드**를
`tpch-sspq/impl/notion_backfill_pending.jsonl`에 기록했다. 대상은 사용자가 지정한 IMP-015 레지스트리
행 페이지 `3aef947f-1be1-816f-b19e-f3679f3e978f`이며, `## 구현 캠페인 tpch-sspq-impl-r1-20260803`
섹션에 IMP-032 기각 내용을 append하는 형태다. discovery 필드
(`Priority`/`Difficulty`/`Expected effect`/`Root cause`/`CUBRID source`/`PostgreSQL source`/
`Evidence level`/`Evidence event`/`Category`/`Queries`/`Status`)는 §10-e에 따라 **불가침**이며 payload에
포함하지 않았다.

## 16. IMP-015와의 관계 — 오해 방지 (중요)

| | IMP-015 | IMP-032 (구 IC-5) |
|---|---|---|
| 상태 | **구현 완료 / accepted (provisional)** | **rejected (착수 전 검증 단계)** |
| 소스 변경 | `query_executor.c` 27 ins / 2 del (1 파일) @ `61f4b4cf9` | **0** |
| 측정 | Q10 −9.92%, CI [0.8991, 0.9223] | 없음 (A/B 미실행) |
| 관계 | IMP-032의 base (spec D2 스태킹, 사용자 승인) | IMP-015 **이후에 더 밀어보려던 후속 시도** |

**IMP-032 기각은 IMP-015의 verdict를 바꾸지 않는다.** IMP-015는 그 자체의 A/B로 accepted(provisional)
이고 브랜치·바이너리·report 모두 유효하다. 이번에 기각된 것은 "IMP-015 다음 단계로 리더
merge/finalize를 병렬화하자"는 **추가 제안**이다.

다만 프로브가 IMP-015에 대해 **적용 범위를 좁히는 사실**을 새로 확보했고, 이는 IMP-015 report §14-a에
기록했다:

- Q15에서는 IMP-015의 런타임-진실 게이트가 병렬 경로를 열지 못한다(그래서 IMP-015 §9의 Q15 +1.0%
  무효과와 정합).
- Q18에서 실제로 병렬화된 것은 IMP-015 변경 (b)(부분 해시리스트 정렬의 무조건 병렬 적격화)이고,
  메인 group-by 폴백 정렬은 여전히 직렬이다.

## 17. 남긴 후속 관찰 (신규 후보 후보군, 이 IMP의 범위 아님)

프로브가 발견한 더 큰 표적: **메인 group-by 폴백 정렬이 IMP-015 하에서도 병렬 게이트를 통과하지
못한다.** 크기는 Q15 정렬 비용 전부(`sort_listfile` 10.00% of 서버 cycles)와 Q18의
`sort_exphase_merge` 16.87%다. 미확정 후보 3개(확정에는 계측 빌드 필요):

1. `sort_check_parallelism`(`external_sort.c:5236-5246`)이 보는 `input_list->page_cnt`가 gather된
   mergeable-list 입력에서 문턱(2048) 미달로 관측되는 경우.
2. `px->parallelism`(= `xasl->parallelism`) 힌트가 해당 XASL 노드에서 `0 또는 1`이어서
   `compute_parallel_degree`가 즉시 0을 반환하는 경우(`px_parallel.cpp:128-131`:
   *"hint >= 0 and < start_degree disables parallel execution"*).
3. `try_reserve_workers` 실패.

이 관찰은 레지스트리 신규 후보로 승격할 가치가 있으나, 새 IMP ID 발급은 §1-b에 따라 **사용자 지시로만**
가능하므로 여기서는 기록만 한다. (편입 시 next_id는 `IMP-033`.)

## §8-c 최종 상태 블록

```yaml
TPCH_SSPQ_IMPL_STATUS:
  campaign_id: tpch-sspq-impl-r1-20260803
  imp_id: IMP-032
  impl_ssot_commit: 276d8e866f0f4702648ccb9b8c00c8c5410931e9
  impl_ssot_blob_sha: 15b42ddca521444fa54b34b0fa8477ed2df643f6
  session_id: 019fc85d-8da5-7000-bc9e-7f97de474072
  stage: IMP_COMPLETE (rejected)
  state: complete
  branch: impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize
  report_commit: (this commit — recorded in implementation-results.json)
  verdict: rejected
  artifact_fingerprint: raw-manifest.json — 38 artifacts, per-artifact sha256
  timestamp: 2026-08-04T13:20:00+09:00
  next_action: none for IMP-032. §17의 후속 관찰은 사용자 지시로만 신규 IMP로 승격.
  source_modified: none
  ab_budget_spent: none
```
