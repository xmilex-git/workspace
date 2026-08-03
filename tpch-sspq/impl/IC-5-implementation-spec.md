# IMP-032 (구 IC-5) implementation spec — GROUP BY 병합·최종화 병렬화 (leader merge/finalize parallelization)

**정식 ID: `IMP-032`** — §1-b의 next_id를 사용자 지시(2026-08-04 그릴링 세션)로 편입.
`IC-5`는 구 개선 후보 레지스트리(⑤)의 별칭으로만 유지한다. 이 파일명(IC-5-…)은
세션 산출물 지정에 따른 것이며, 본문·브랜치·장부의 정식 ID는 IMP-032다.
편입 후 registry next_id는 `IMP-033`.

Status: specification only, produced by a grilling session on 2026-08-04.
**This document does not authorize Phase 2.** The IMPL-SSOT phase gate stands. When
Phase 2 starts for IC-5, this spec is lifted into the candidate worktree's
`implementation-plan.md` (IMPL-SSOT §5-c) after the section-A assumptions are verified
against the pinned source.

Notion card: `IC-5` (⑤ GROUP BY 병합·최종화 병렬화, page `3adf947f-1be1-81e8-acb5-f583ec2e4a2a`),
source locations `external_sort.c:5232, 5829, 5841` (verified against the IMP-015
worktree at `61f4b4cf9`: `:5232` = `sort_check_parallelism()` SORT_GROUP_BY branch;
`:5829` = `sort_merge_worker_runs_to_one()` call (leader fan-in merge, phase ②);
`:5841` = `sort_run_final_single()` call (leader per-tuple `put_fn` drain, phase ③)).

Predecessor contract: IMP-015 spec D3 (IC-5 strictly after IMP-015; consumes IMP-015's
re-measured residue as baseline) and D5 (`agg_hash_respect_order` parallel-time policy is
an explicit IC-5 design item). IMP-015 verdict: accepted (provisional), Q10 -9.92%
CI [0.8991, 0.9223]; leader merge/finalize is the dominant residue (Q10 trace: GROUPBY
3457 ms total vs 128..132 ms worker share).

---

## Decisions

### D1 — 착수 전 경량 귀속 프로브 (attribution probe), 풀 텔레메트리 아님
IC-5의 타깃 크기(리더 잔여 직렬)와 그 내부 분해(② merge vs ③ finalize)는 아직
측정된 적이 없다 — 카드의 69.8%/50.1% 밴드는 구 측정 레짐·IMP-015 이전 세계의
프로파일 밴드이며, AMEND-F에 따라 자동으로 제거가능 효과가 아니다.

- **Phase 2 착수 시 첫 행동**(이 세션에서는 실행하지 않음): 보존된 IMP-015 바이너리
  (`install/IMP-015`, patch `61f4b4cf9`, §6-a-1 RelWithDebInfo 핀 레시피 — 재빌드 없음)로
  서버를 띄우고 Q15/Q18 각각 **워밍업 1회 + SET TRACE ON 1회**를 실행하며
  `perf record`를 붙인다. 트레이스가 GROUPBY 총시간·워커 몫을, perf 샘플이
  `sort_merge_queue_run`(②) vs `sort_put_result_from_tmpfile`/`qexec_gby_put_next`(③)
  귀속을 준다.
- 이 프로브는 **귀속 증거(attribution evidence)이며 A/B 증거가 아니다**: §6-c 블록
  규율·quiet-gate 차단을 적용하지 않고 bgload 기록만 남긴다(호스트 상주 pxidx
  `cub_server`로 인한 게이트 재시도 예산 소모 회피 — §3-b 불가침 유지).
- 기대효과 산정 규율(IMP-015 §8 교훈의 성문화): **기대치는 "프로브로 측정된 리더
  잔여 × 논증된 제거가능 분율(Amdahl)"로만 산출한다. 구 레짐 밴드·이종 경로
  절대치의 이관은 금지.** 산출 기대효과가 대상 질의의 MDE(주: corrected MDE는
  Phase 1A 부재로 없음 — IMP-015 §5와 동일하게 라벨링된 restart-regime 대체 MDE 사용)
  미만이면 `UNPROVABLE_ON_THIS_HOST`를 기록하고 착수 여부를 사용자에게 되묻는다.
- IMP-015 `carried_risks`(TWU-unmeasured, 10b-item7-reduced)는 이 프로브로 닫지
  않는다 — close_by는 원래대로 cumulative-phase telemetry pass (IMP-015 장부이지
  IC-5 블로커가 아님).
- 성능 수치는 항상 RelWithDebInfo 핀 레시피 빌드에서만 잰다. 진단 빌드
  (assertion/sanitizer)는 정합성 전용이며 시간 측정에 쓰지 않는다.

### D2 — base: IMP-015 패치 위 스태킹 (사용자 명시 승인, 2026-08-04)
§5-b 요건 충족: 사용자가 이 그릴링 세션에서 스태킹을 명시 승인했다.

- 근거(소스 확인): 리더 병합(② `sort_merge_worker_runs_to_one`)·최종화(③
  `sort_run_final_single`) 기계장치는 병렬 경로가 발동해야만 실행되는데, IMP-015 없는
  base에서는 hash-eligible 플랜(Q10/Q15/Q18 전부)이 `sort_check_parallelism`의
  `hash_eligible` 게이트에서 직렬로 떨어져 그 경로에 도달하지 않는다. 독립 브랜치는
  효과 측정이 불가능한 죽은 선택지.
- 브랜치: `impl/tpch-sspq-impl-r1-20260803/IMP-032-<slug>`(§5-b 형식)를
  `61f4b4cf9`(IMP-015 patch commit)에서 분기, IMP-032 커밋만 얹는다
  (one-branch rule은 "IMP-032의 변경만 추가"로 유지).

### D3 — ID 편입: IMP-032 (사용자 지시, 2026-08-04)
구 후보 레지스트리 항목 IC-5(⑤)를 `IMP-032`로 편입한다 (§1-b: 새 IMP ID는 사용자
지시로만). `implementation-results.json` 레코드 키·브랜치명·report 경로 모두
IMP-032를 쓰고, "구 IC-5(⑤)" 매핑을 report와 Notion 카드에 명기한다.
next_id는 `IMP-033`이 된다.
- A/B 설계: **B = IMP-015 바이너리(보존본, 재빌드 없음), P = IMP-015+IC-5** —
  IC-5 단독 효과를 격리.
- 기록 의무: IMP-015 report와 IC-5 report 양쪽에 스태킹 승인 기록 (§5-b).
- 명기된 리스크: cumulative 단계에서 IMP-015가 뒤집히면 IC-5 측정도 무효.

### D2-P — 설계 원칙 (사용자 지시, 2026-08-04)
모든 후속 결정(특히 스코프 분해·기계장치 선택)은 다음 세 원칙으로 판정한다:
1. **최소수정** — 변경 반경 최소화, §5-d LOC 밴드 준수.
2. **최대 성능 이득** — 프로브(D1)로 측정된 리더 잔여 중 가장 큰 국면을 우선 공략.
3. **최대 기존 함수 재사용** — 새 기계장치 발명보다 기존 merge/큐/워커 헬퍼의
   재조합·일반화를 우선 (유지보수성·추상화 강화).

### D4 — 스코프: 카드 요소 3 단독 ("그룹 경계 정렬 분할 + 워커별 병렬 finalize drain"), ORDER_BY 병렬 패턴 동화 (사용자 확정, 2026-08-04)

카드의 구현방향 3요소 분해:
- **요소 3 (range partition finalize) = 이번 스코프의 전부.** SORT_ORDER_BY 병렬
  경로가 동일한 골격을 이미 완비하고 있음을 소스로 확인: fan-in 후
  `sort_split_last_run()`(페이지 단위 분할) → `SORT_EXECUTE_PARALLEL(...,
  sort_put_result_for_parallel)`(워커별 병렬 drain, 워커별 출력 리스트) →
  `qfile_connect_list`/`qfile_append_list`로 순서대로 연결 →
  `qfile_reopen_list_as_append_mode`. GROUP_BY의 `sort_merge_worker_runs_to_one`
  주석이 명시하듯 GROUP_BY만 이 골격 직전에 멈추고 직렬 `sort_run_final_single`로
  빠진다 — IC-5(IMP-032)는 그 멈춤을 제거하고 같은 골격에 합류시킨다.
- **요소 2 (finalize가능/순서의존 분류) = 독립 작업이 아니라 경계 논증으로 흡수.**
  분할점을 그룹 경계에 정렬하면 각 그룹은 통째로 한 워커 구간에 들어가고, 워커는
  직렬과 동일한 순서로 동일한 튜플을 보므로 SUM/AVG/COUNT는 물론 order-sensitive
  aggregate(GROUP_CONCAT 등)까지 의미가 보존된다. partial aggregate merge가 없으므로
  분류할 대상이 없다. 단 그룹 경계를 가로지르는 전역 상태(ROLLUP super-group 등)는
  분류가 아니라 **직렬 폴백 게이트**로 처리(해당 시 기존 `sort_run_final_single`
  경로 유지).
- **요소 1 (계층형 merge, ② 병렬화) = 이번 스코프에서 제외.** ③ finalize는 튜플당
  집계 누적, ② merge는 스트리밍 비교뿐이라 ③ 지배가 유력하며 D1 프로브가 판정한다.
  프로브가 ② 지배를 보이면 별도 결정으로 재소환.

**기존 의미론 동화 계획 (사용자 지시: 기존 코드 의미론과 최대한 유사하게, 녹아들게):**

1. `external_sort.c` — 새 함수 발명 최소화, ORDER_BY 분기 미러링:
   - GROUP_BY fan-in 이후 흐름을 ORDER_BY와 동일 순서로 재구성:
     `sort_split_last_run()`은 **수정 없이 그대로 재사용**(페이지 단위 분할 유지).
   - `sort_put_result_for_parallel()`에 기존 `if (px_type == SORT_ORDER_BY)` 분기와
     대칭인 `SORT_GROUP_BY` 분기를 추가(워커별 출력 리스트 open/close — ORDER_BY
     분기의 문장 구조·명명을 그대로 따름).
   - **그룹 경계 정렬**은 분할을 바꾸지 않고 drain에서 지역적으로 처리: 워커 i는
     (i) 자기 첫 페이지의 선두에서 직전 구간 마지막 그룹의 연속 튜플을 건너뛰고
     (직전 구간 마지막 튜플의 키와 비교), (ii) 자기 마지막 페이지를 넘어 현재
     그룹이 닫힐 때까지 계속 읽는다. 비교는 기존 정렬키 비교 함수 재사용.
   - 최종 연결 coda(`qfile_connect_list`/`qfile_append_list`/
     `qfile_reopen_list_as_append_mode`)는 ORDER_BY의 것을 그대로 재사용.
2. `query_executor.c` — put_arg 복제 패턴 미러링: ORDER_BY가 워커별 `SORT_INFO`를
   두듯 GROUP_BY도 워커별 `GROUPBY_STATE`(자기 집계 누산기 + 자기 출력 리스트)를
   둔다. 복제·해제는 기존 gbstate 초기화/clear 함수(`qexec_..._groupby_state`)를
   재사용해 구성하고, 신규 헬퍼가 필요하면 기존 명명 규칙(`qexec_gby_*`)을 따른다.
3. 직렬 폴백 게이트: ROLLUP 등 부적격 조건이면 기존 `sort_run_final_single` 경로를
   그대로 탄다 — 기존 경로는 삭제하지 않고 게이트 뒤에 보존(회귀 반경 최소화).

수정 반경(예상): `external_sort.c`(GROUP_BY 분기 합류 + drain 경계 조정),
`query_executor.c`(워커별 gbstate), 헤더 소폭. XASL/영속 포맷/락 프로토콜 불가침
(§5-d 조건 접촉 시 stop-and-report).

### D5 — `agg_hash_respect_order` 유지 (기본 `y`, 플립 없음; 사용자 명시 승인, 2026-08-04)
IMP-015 D5의 이월 항목을 종결한다. 판단 근거(수치·구조 논증):
- D4의 range-partition finalize는 워커별 출력 리스트를 키 순서대로 연결하므로 최종
  출력이 직렬과 동일한 그룹키 정렬 순서다 — **순서 계약을 유지한 채 리더 잔여의
  병렬 이득을 전부 취할 수 있고, `n` 플립이 이 스코프에서 추가로 여는 이득은 0**이다.
- 이 파라미터가 이득을 여는 경로(`query_executor.c:5469`: 해시 성공·무spill 시 정렬
  생략, 해시테이블 직접 출력)는 정렬 제거 계열(IMP-016/021)의 영역이지 IMP-032가
  아니다.
- 플립 비용: 사용자 가시 GROUP BY 출력 순서가 런타임 병렬 결정에 종속 — IMP-015
  D5가 기각한 계약 위반. D4의 order-sensitive aggregate 의미 보존 논증도 유지를
  전제로 성립한다.

### D6 — 검증 체제: OptDebug 진단 게이트(면제 불가) + 2층 TC + latch 스트레스 (사용자 확정, 2026-08-04)

1. **진단 빌드 게이트 — 면제 불가.** IMP-015의 면제 근거("기존 배포 경로의 입력
   집합만 변경")는 IMP-032에 성립하지 않는다: ③ 병렬 drain은 GROUP_BY가 처음으로
   `sort_put_result_for_parallel` 골격에 합류하는 신규 경로이고, 워커별 gbstate라는
   신규 복제·공유 상태가 생긴다.
   - 진단 빌드는 **OptDebug(assertion-enabled)만** 사용한다. **ASAN/TSAN은 사용하지
     않는다**(사용자 지시, 2026-08-04: CUBRID 고질적 비호환). **gdb를 응용한 검증은
     엄격히 금지**(사용자 지시, 동일).
   - OptDebug 빌드에서 전체 TC 배터리 + Q01–Q22 결과 스모크 통과가 게이트.
     성능 수치는 절대 OptDebug에서 재지 않는다(D1의 RelWithDebInfo 원칙).
   - 이 게이트는 스펙 개정(사용자 승인) 없이 면제할 수 없다.
2. **TC — D6(IMP-015) 방식 2층, 캠페인 하니스 수용.**
   - 1층(SQL 정합성): HS_REJECT_ALL 강제 데이터 + `max_agg_hash_size` 축소 spill 강제,
     직렬 참조와 §6-b 완전 일치. 분할 경계 특화 적대 케이스 포함:
     (i) 페이지 경계 주변 중복 키 밀집(그룹이 경계 관통), (ii) 단일 거대 그룹
     (전 구간 관통 퇴화), (iii) 그룹 수 < 워커 수, (iv) ROLLUP → 직렬 폴백 게이트
     발동 확인, (v) GROUP_CONCAT/order-sensitive 직렬 동일 출력, (vi) 빈 입력/1행/
     전부-NULL 키.
   - 2층(shell 발동증명): 트레이스에서 ③ 병렬 drain 식별 신호를 grep. 신호는 기존
     GROUPBY px 통계 필드(`px_min/max_groupby_*`) 명명을 따라 finalize 국면으로
     확장하고, base(IMP-015 단독) 바이너리에는 부재함을 함께 확인(무단 되돌림 탐지).
3. **latch 계열 스트레스.** IMP-015 §3 도메인 지식 승계(open-for-append 리스트
   writer-latch vs 워커 dead-latch, `qfile_close_list` 처방). IMP-032 신규 하중:
   (i) 워커들의 consolidated run 임시파일 동시 읽기 + 경계 페이지 이웃 워커 중복
   읽기, (ii) 워커별 출력 리스트 동시 append. 동시 csql 다중 세션 × 반복 스트레스
   런 + 서버 에러로그 latch timeout 부재 확인을 게이트로 한다.

### D7 — 대상 질의·컨트롤 배치 (사용자 확정, 2026-08-04)
- **1차 타깃 Q15**: §6-c/6-d 완전 규율 A/B(3사이클 B→P→P→B, paired bootstrap CI
  게이트). 근거: IMP-015 §9에서 Q15의 직렬 group-by 국면은 미개선(+1.0% 무효과)으로
  남았고 IC-5(IMP-032)의 1차 타깃으로 명시 이월됨.
- **관측 타깃 Q18**: armed observation, 스트림 2-블록(IMP-015 §9 방식). 게이트 아님.
- **Q10 비대칭 가드**: B(IMP-015) 대비 3% 초과 회귀 없음이 게이트 — IMP-015가 확보한
  -9.92%를 까먹지 않는지의 무회귀 검사. 개선이 나오면 기록하되 게이트로 삼지 않음.
- **순수 부정 컨트롤(±3% 무변화 + 플랜 모양 불변)**: Q11(1,516페이지 < 2048 문턱,
  null-by-size 유지), Q16(post-sort 소비 루프는 IMP-023 영역 — diff가 그 루프를
  건드리지 않음을 코드 리뷰로도 확인), Q01/Q03/Q05.
- 기대효과·MDE 판정(D1)·`UNPROVABLE_ON_THIS_HOST` 판정 대상은 1차 타깃 Q15로 고정.
- 측정 예산: Q15 A/B 3사이클 + 스트림 1사이클(Q18·컨트롤 일괄) — IMP-015와 동일
  규모로 pxidx 상주 하의 게이트 재시도 예산 내 운용.

---

## A. 착수 전 소스검증 가정 (첫 소스 수정 전, 핀 소스 `61f4b4cf9` 스택 기준)

| # | 가정 | 기대 답 | 반증 시 |
|---|---|---|---|
| A1 | consolidated run 임시파일의 페이지 경계는 튜플 경계다(레코드가 run 페이지를 걸치지 않거나, 걸침(long record)이 drain에서 이미 처리됨) — `sort_split_last_run` 페이지 분할을 그대로 쓰는 전제 | holds | 분할 단위를 튜플 경계 보장 지점으로 조정; LOC 밴드 재산정 |
| A2 | `sort_put_result_from_tmpfile`가 임의 `start_index`에서 시작 가능하고(ORDER_BY가 이미 사용), 조건부 정지(경계 skip/overrun 확장)를 지역 수정으로 수용한다 | holds | drain 래퍼 신설로 전환; ORDER_BY 경로 불변 유지 |
| A3 | `GROUPBY_STATE`는 워커별 복제가 가능하다: 집계 누산기·출력 리스트·작업 DB_VALUE 버퍼에 리더 전역 은닉 상태(공유 val_list/regu var 인스턴스 상태 등)가 없다, 또는 있으면 열거·복제 가능하다 | holds | **stop-and-report** — 복제 불가능한 상태가 있으면 스코프 재설계(부분 직렬화) 여부를 사용자가 결정 |
| A4 | 직렬 폴백 게이트 조건이 게이트 시점에 판별 가능하다: ROLLUP(`g_dim_levels > 1` 상당) 및 그룹 경계를 가로지르는 기타 전역 상태(composite lock, instnum 계열 등)의 전수 열거 | enumerable | 열거 불가 항목 발견 시 해당 케이스를 폴백 게이트에 보수적으로 추가 |
| A5 | `qfile_connect_list`/`qfile_append_list`/`qfile_reopen_list_as_append_mode` coda가 group-by 출력 리스트 타입·플래그에서도 ORDER_BY와 동일하게 순서 보존 동작한다 | holds | coda 대체 경로 설계 후 LOC 재산정 |
| A6 | `GROUPBY_STATS`에 ③ finalize 국면 px 통계 필드 확장이 기존 `px_min/max_groupby_*` 명명으로 수용 가능하다(발동증명 신호, D6-2층) | holds | 발동증명 신호를 별도 카운터로 재설계 |
| A7 | 워커 스레드 문맥(`SORT_EXECUTE_PARALLEL` 진입 preamble: tran_index/conn_entry 승계)에서 집계 누적·finalize 함수(`qexec_gby_*`, `qdata_*`) 호출이 안전하다 — 리더 전용 전제(트랜잭션/에러 컨텍스트)가 없다 | holds | 리더 전용 의존 발견 시 **stop-and-report** |
| A8 | phase ①에서 예약한 워커(`px_worker_manager`)를 ③ drain에 재사용할 수 있다(추가 예약 없음 — ORDER_BY와 동일) | holds | 예약 정책 별도 설계; ORDERBY 예약 경합(IMP-015 §8) 재평가 |

## B. `implementation-plan.md` 매핑 (IMPL-SSOT §5-c 항목 1–10)

1. **가설(반증 가능).** IMP-015 이후 group-by 폴백 정렬의 잔여 병목은 리더 직렬
   국면(② fan-in 병합 + ③ 튜플당 put_fn drain)이며, 그중 ③을 그룹 경계 정렬 분할로
   병렬화하면 Q15 wall이 "D1 프로브로 측정된 ③ 몫 × Amdahl 제거가능 분율"만큼
   줄고(수치는 프로브 후 기입), paired bootstrap 95% CI가 1.0 아래로 내려가며,
   결과는 §6-b 완전 일치를 유지한다.
2. **변경 `file:line` (핀 `61f4b4cf9` 기준).** `external_sort.c:5829-5847`(GROUP_BY
   분기의 fan-in 이후를 ORDER_BY 골격에 합류), `sort_put_result_for_parallel()`
   (`:3290대`, SORT_GROUP_BY 분기 추가 + 경계 skip/overrun), `query_executor.c`
   gbstate 준비부(워커별 복제). **불변·하중 지지:** `sort_split_last_run:3387`(그대로
   재사용), `sort_merge_worker_runs_to_one:5627`(② 유지), ORDER_BY coda
   (`:4890-4960`), `sort_check_parallelism` GROUP_BY 분기(`:5228대`, IMP-015 소유).
3. **PostgreSQL 참조 (핀 `5713b437`).** `planner.c` gather_grouping_paths 계열 및
   `nodeAgg.c` partial/finalize 분리 — 단 **참조는 대조로 기록**: PG는 워커 partial
   aggregate + Gather + Finalize(직렬)로 푸는 반면, IMP-032는 집계를 단일 사본으로
   유지한 채 drain을 range 분할 병렬화한다(카드 요소 3). PG에 직접 대응물은 없으며
   이 괴리와 그 이유(D2-P: 최소수정·기존 기계장치 재사용)를 plan에 명기한다.
4. **변경 파일 / LOC 밴드.** `external_sort.c`, `query_executor.c`(+헤더 소폭).
   LOC low 50 / likely 140 / high 280. §5-d 하드스톱 = 420 LOC 또는 예상 밖 서브시스템
   /XASL 직렬화/영속 포맷/락 프로토콜 접촉.
5. **기대 메트릭 시그니처.** Q15 트레이스: GROUPBY에 ③ finalize px 통계(신규 필드,
   A6) `N ≥ 2` 출현(base=IMP-015에는 부재); D1 프로브 재실행에서 ③ 귀속
   (`sort_put_result_from_tmpfile`/`qexec_gby_put_next` 샘플 점유) 감소; GROUPBY
   time 감소. group count·spill bytes·행수는 불변(§7-d 작업량 안정성 — 카드 검증
   기준의 group count/spill bytes 항목은 여기로 흡수). serial_tail/TWU의 공식 비교는
   cumulative-phase telemetry pass로 이월(D1) — 카드 검증 기준 중 해당 항목은
   프로브 수준 귀속 증거로 대체됨을 명기.
6. **정합성 리스크·시험.** D6 전체(OptDebug 면제 불가 게이트, 2층 TC + 경계 적대
   케이스, latch 스트레스). 카드 검증 기준의 SUM/AVG/COUNT·DISTINCT·overflow·
   order-sensitive 회귀는 1층 TC 배터리에 포함(DISTINCT aggregate·수치 overflow
   케이스를 D6-2 목록에 추가 적용).
7. **대상 질의.** Q15(1차, 게이트), Q18(관측), Q10(비대칭 가드) — D7.
8. **부정 컨트롤.** Q11, Q16, Q01/Q03/Q05 — D7. 플랜 모양·추정치 캠페인 전역 불변
   (executor-only 변경).
9. **중복·의존.** IMP-015: 스태킹 base(D2, 사용자 승인) — cumulative에서 IMP-015가
   뒤집히면 IMP-032 측정 무효. IMP-016/017/021: 정렬 제거·해시 유지 계열로
   anti-additive(해시가 성공하면 이 경로 자체가 축소). IMP-023: Q16 post-sort 소비
   루프 — 불가침. 구 카드 ⑳(Q10 barrier 제거): 연동하되 동일 후보 아님(카드 메모).
   `agg_hash_respect_order`: D5로 종결(유지).
10. **롤백.** 후보 브랜치의 IMP-032 커밋 단일 revert. 런타임 완화책으로 직렬 폴백
    게이트가 존재하나 이는 롤백 수단이 아니라 정합성 게이트다(혼동 금지).

## C. 검증 기준 처분 (카드 §검증 기준 대비)

| 카드 기준 | 처분 |
|---|---|
| serial_tail_seconds·TWU 비교 | 프로브 수준 귀속 증거(D1)로 착수 전·후 비교; 공식 텔레메트리 비교는 cumulative-phase로 이월. **절대 wall 목적지 게이트는 두지 않는다** — IMP-015 §5/§8·carried_risk `expectation-transfer` 규율("기대치는 동일 경로 상대비로만 이관") 적용, 게이트는 상대 CI(§7-a-2)와 MDE(§7-a-3)만 |
| group count·spill bytes 비교 | §7-d 작업량 안정성 검사로 흡수(불변이어야 함 — 변하면 A/B_CONFOUNDED) |
| SUM/AVG/COUNT·DISTINCT·overflow·order-sensitive 회귀 | D6 1층 TC 배터리(경계 적대 케이스 포함)로 전부 수용 |
