# IMP-032 (구 IC-5) — Phase 2 중간 상태 기록 (역사적 문서)

> **최종 처분: `rejected`** — 2026-08-04 사용자 결정. 정식 §10-b 산출물은 이 디렉터리의
> `report.md`이며 그것이 권위 문서다. 이 문서는 결정 **직전**, 두 정지 조건에 걸려 멈춘 시점의
> 상태를 그대로 보존한 기록이다(당시에는 verdict가 없어 report.md를 만들지 않았다). 아래 §5의
> 선택지 A–E 중 사용자가 **(D) 기각**을 택했다.

## 1. Identity와 핀

| 항목 | 값 |
|---|---|
| IMP ID | `IMP-032` (구 개선 후보 레지스트리 `IC-5` / ⑤ — spec D3에 따른 편입, next_id는 `IMP-033`) |
| lane | performance |
| 캠페인 | `tpch-sspq-impl-r1-20260803` |
| IMPL-SSOT | commit `276d8e866f0f4702648ccb9b8c00c8c5410931e9`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` (§1-d 7단계 전수 검증 통과, 드리프트 없음) |
| 확정 스펙 | `tpch-sspq/impl/IC-5-implementation-spec.md`, blob `580cd4f5f17ab47b3418352d1aed18689aa9e258` |
| CUBRID base SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (동결) |
| 브랜치 | `impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize` @ `61f4b4cf967dbc2f0cd18422b83561ef44366382` 에서 분기 |
| 브랜치 자체 커밋 | **0개** — 소스 수정 없음 (worktree clean) |
| 스태킹 | spec D2 / §5-b: 사용자 명시 승인(2026-08-04) 하에 IMP-015 패치 위 스태킹. A/B 설계는 B=IMP-015 보존 바이너리, P=IMP-015+IMP-032 |
| diffstat | 없음 (변경 0) |

## 2. 수행한 것

1. **§1-d 핀 검증** — 통과. (`work/IMP-032/status/G001-pin-and-worktree.md`)
2. **§A A1–A8 착수 전 소스검증** — 전수 수행. → `A1-A8-source-verification.md`
   - A1/A2/A4/A5/A6/A8 **holds**, A7 **조건부 holds**, **A3 반증**.
3. **D1 귀속 프로브** — 보존 `install/IMP-015` 바이너리로 Q15/Q18 워밍업 1회 + `SET TRACE ON` 1회 +
   `perf record`. → `D1-attribution-probe.md`
   - 라벨: **귀속 증거이며 A/B 증거가 아니다.** quiet-gate 차단 미적용(bgload 기록만), 재빌드 없음.
4. **raw manifest** — 38개 산출물의 절대경로/바이트/sha256/생성명령/핀 기록. → `raw-manifest.json`

수행하지 않은 것과 이유:

- `implementation-plan.md`(§5-c): 스코프가 미확정이라 항목 2(변경 file:line)·4(LOC 밴드)·6(정합성
  시험)을 정직하게 쓸 수 없다. 스코프 결정 후 작성한다.
- 소스 수정·D6 정합성 게이트·D7 A/B: 아래 정지 조건으로 차단. §6-c의 B→P→P→B 예산을 쓰지 않았다.
- Notion: verdict도 `report_commit`도 없어 §10-c(Git first) 순서상 아직 쓸 것이 없다. discovery 필드
  (`Priority`/`Difficulty`/`Expected effect`)는 §10-e에 따라 불가침 — 손대지 않았다.

## 3. 정지 조건 ① — spec §A A3 반증 (stop-and-report)

`GROUPBY_STATE`의 워커별 복제가 spec이 선언한 수정 반경(`external_sort.c`, `query_executor.c`,
헤더 소폭) 안에서 **불가능**하다.

복제 가능: 차원별 누산기(`qexec_gby_init_group_dim`이 이미 `db_value_copy`로 복제 —
`query_executor.c:20258-20283`), 워커별 출력 리스트, 작업 버퍼.

복제 **불가능**한 리더 전역 은닉 상태 (A3가 반증 예시로 명시한 항목 그대로):

- 공유 `g_val_list` / `g_regu_list` 인스턴스 — `qexec_gby_agg_tuple`이 튜플마다
  `fetch_val_list`로 XASL 소유 DB_VALUE에 쓰고(`:4587`) `qdata_evaluate_aggregate_list`가 같은
  값을 읽는다(`:4597`).
- `g_output_agg_list` — finalize가 XASL 소유 DB_VALUE에 결과를 옮긴다(`:19947-19948`); 이 값이
  outptr/having regu 트리의 바인딩 지점이다.
- `having_pred`·`g_outptr_list`·공유 `xasl_state->vd` (`:19973`, `:20047-20048`, `:20081`).
- `agg_hash_context` 부분리스트 단일 순차 커서(`:5191-5228`, `:5250-5309`) — XASL을 복제해도
  복제본의 컨텍스트는 비어 있어 리더의 spill 산출물을 대신하지 못한다.
- `grbynum_val` + `SORT_PUT_STOP` 단발 발화, 비원자적 `groupby_stats.rows++`, `composite_lock`.

**ORDER_BY 미러링이 성립하지 않는 이유**: ORDER_BY의 병렬 drain `qexec_ordby_put_next`는 순수 튜플
복사이고 XASL 표현식 평가가 없다. 게다가 소스에 이미 결정이 적혀 있다 —
`external_sort.c:5720-5722`: *"put_fn must not run in parallel because ordbynum_val state is shared
and SORT_PUT_STOP must fire exactly once"*. `ordbynum_val` 하나 때문에 ORDER_WITH_LIMIT도 직렬
drain을 택한다.

**복제 기계장치는 존재하지만 반경 밖**: 병렬 scan은 워커별 XASL 전체 복제로 해결한다
(`px_scan_task.cpp:569-643` — `xcache_find_xasl_id_for_execute` 또는 `stx_map_stream_to_xasl`
+ 워커별 `xasl_state`/`VAL_DESCR`). 이를 도입하면 §5-d의 "XASL 직렬화 / 미예상 서브시스템" 접촉이며
LOC 하드스톱 420을 넘는다.

## 4. 정지 조건 ② — spec D1 `UNPROVABLE_ON_THIS_HOST` (Q15)

D1 프로브 측정 결과:

| 질의 | GROUPBY 상태 | 병렬 폴백 정렬 | ③ `sort_put_result_from_tmpfile` | ② `sort_merge_nruns` |
|---|---|---|---|---|
| **Q15** (1차 게이트) | `hash: partial` (HS_REJECT_ALL) | **미발동** | 표본 **0** / 5,088 | 표본 **0** |
| **Q18** (관측) | `hash: partial` | 발동 — 단 **해시 부분리스트 정렬**만 | 표본 716 / 10,684 (6.70%) | 표본 103 (0.96%) |

- Q18의 ③ 표본 716개 중 **688개가 `qexec_hash_gby_put_next`와 동시 출현**, `qexec_gby_put_next`와
  동시 출현하는 표본은 **0개**. ⇒ 병렬화된 것은 IMP-015가 무조건 병렬 적격화한 **부분 해시리스트
  정렬**이고, **메인 group-by 폴백 정렬은 Q15·Q18 모두 직렬**이다
  (`sort_exphase_merge` 1,700 표본 아래 `qexec_gby_put_next` 1,203 표본).
- 원인 절단: 뷰 본문 단독 실행도 직렬, 12개월 창(9,123,688행 / sort page 85,534)에서도 직렬
  ⇒ 크기 문턱(2048)·상위 질의 구조·해시 상태 모두 원인이 아니다.
- 기대효과 산정(D1 규율 "측정된 리더 잔여 × 논증된 Amdahl 분율"): Q15의 리더 잔여 측정치가 **0.00%**
  이므로 기대효과 = **0.00%**. §6-d의 MDE 하한이 `max(1%, 2×CV)`이므로 대체 MDE의 정확한 값과
  무관하게 `0.00% < 1%` ⇒ **`UNPROVABLE_ON_THIS_HOST`**.
- 부수 확인: 그 유일한 병렬 인스턴스 내부에서는 ③이 ②를 **87.4 : 12.6**으로 압도 —
  spec D4의 "③ 지배" 가정 자체는 (그 인스턴스에 한해) 참이다.

## 5. 사용자 결정이 필요한 선택지

- **(A) 스코프 재설계 승인** — px_scan식 워커별 XASL 복제를 도입. spec 개정 + LOC 밴드 재산정(추정
  600–1200) + §5-d XASL 직렬화 접촉 승인 필요. **단 이것만으로는 Q15에서 효과가 나오지 않는다**
  (정지 조건 ②가 그대로 남는다).
- **(B) 카드 요소 1로 피벗** — ② 계층형 fan-in merge 병렬화. `sort_merge_queue_*`는 키 비교와 페이지
  I/O뿐이라 A3 문제가 원천적으로 없다(spec D4가 "프로브가 ② 지배를 보이면 별도 결정으로 재소환"으로
  문을 열어 둠). **단 프로브는 ②가 ③보다 작다고 측정했다(0.96% vs 6.70%)** — 그리고 둘 다 Q15에는
  존재하지 않는다.
- **(C) 부분 직렬화** — ③ drain의 비-XASL 부분만 프리페치로 겹치기. 이득 상한이 낮고 Q15에는 적용 대상
  자체가 없다.
- **(D) IMP-032 연기/기각** — 표적이 Q15에 존재하지 않는다는 측정 사실을 근거로.
- **(E) 신규 후보로 전환 (권고)** — 프로브가 발견한 실제 병목은 "**메인 group-by 폴백 정렬이 IMP-015
  하에서도 병렬 게이트를 통과하지 못한다**"는 것이다. Q15 정렬 비용 전부와 Q18의
  `sort_exphase_merge` 15.9%가 여기에 있다. 이는 IMP-032의 ③ 병렬화보다 **큰** 표적이며 IMP-015의
  게이트/배관 후속 작업이다. 남은 후보는 `sort_check_parallelism`(`external_sort.c:5236-5246`)의
  `input_list->page_cnt`가 gather된 mergeable-list 입력에서 문턱 미달로 보이는 경우,
  `px->parallelism`(=`xasl->parallelism`) 힌트가 해당 XASL 노드에서 `0 또는 1`이어서
  `compute_parallel_degree`가 즉시 0을 돌려주는 경우(`px_parallel.cpp:128-131`),
  `try_reserve_workers` 실패다. 확정에는 계측 빌드(= 첫 소스 수정)가 필요해 정지 상태에서 수행하지
  않았다.

## 6. §8-c 상태 블록

```yaml
TPCH_SSPQ_IMPL_STATUS:
  campaign_id: tpch-sspq-impl-r1-20260803
  imp_id: IMP-032
  impl_ssot_commit: 276d8e866f0f4702648ccb9b8c00c8c5410931e9
  impl_ssot_blob_sha: 15b42ddca521444fa54b34b0fa8477ed2df643f6
  session_id: 019fc85d-8da5-7000-bc9e-7f97de474072
  stage: G004-complete / G003-G005-G006-G007 blocked
  state: blocked
  branch: impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize
  report_commit: null
  verdict: null
  artifact_fingerprint: raw-manifest.json (38 artifacts, sha256 per artifact)
  timestamp: 2026-08-04T02:05:00+09:00
  next_action: 사용자 결정 (A)~(E) 대기. 결정 전 첫 소스 수정 금지.
  source_modified: none
  ab_budget_spent: none
```
