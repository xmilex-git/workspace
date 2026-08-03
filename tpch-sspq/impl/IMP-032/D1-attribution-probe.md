# IMP-032 (구 IC-5) — D1 귀속 프로브 결과

**라벨: 귀속 증거(attribution evidence)이며 A/B 증거가 아니다.** §6-c 블록 규율(B→P→P→B, 3 measured
runs)과 quiet-gate 차단을 적용하지 않았고, bgload는 기록만 했다. 재빌드 없음 — 보존
`install/IMP-015` 바이너리만 사용. 여기의 어떤 수치도 성능 A/B 결과로 인용해서는 안 된다.

## 0. 실행 계약과 환경 (기록)

| 항목 | 값 |
|---|---|
| 캠페인 / IMP | `tpch-sspq-impl-r1-20260803` / `IMP-032` (구 IC-5) |
| IMPL-SSOT | commit `276d8e866f0f4702648ccb9b8c00c8c5410931e9`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` |
| 바이너리(B) | `install/IMP-015/bin/cub_server` sha256 `0a376e0606f7395822cf0f4925b8290326b4f1131e6c865e5e7b291722726f30`, Build ID `379ab8c0760ec526fbeee8b80f0a2da0d81759bd` (재빌드 없음) |
| runtime conf | `install/IMP-015/conf/cubrid.conf` sha256 `ad19f5ac1e7e983e4a0b1c113d21e25e096d02d3160445f9d10a2e8b6d9cb9ff` = §6-a-2 핀 일치 |
| `CUBRID_TMP` | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/tmp` (§6-a-2 어서션 통과) |
| CPU / NUMA | SUT `taskset -c 0-15` + `numactl --membind=0`, collector(perf) `20-23` (§3-a) |
| all-TID affinity | 126 TID, `off_sut_tids=[]` (start 직후 검증) |
| §3-b ownership | 시작 전 `FREE` → 시작 후 `OK` (`executable_under_campaign_prefix=true`, port 1523, db `tpch_sf10_q1`) |
| bgload (기록만) | start 블록 mean 0.384 / p95 0.67 / max 0.882 core-s/s, `CLEAN`; end 블록 동일 판정 (threshold 6.0은 **차단에 사용하지 않음**) |
| 서버 정지 | 프로브 종료 후 `cubrid server stop` 성공, `cub_server` 부재 확인 |

### 0-a. 선행 정리 조치 (§3-b 근거 기록)

프로브 시작 시 `install/IMP-015/bin/cub_master` (PID 3221464)가 상주하며 TCP 1523을 점유하고 있었다.
`/proc/3221464/environ`에서 `CUBRID_TMP=/home/cubrid/CUBRID/var/CUBRID_SOCK` — **§6-a-2 핀 위반**
(캠페인 temp가 아님) 이며 부착된 `cub_server`는 0개였다. `/proc/exe`가 캠페인 install prefix 아래이므로
§3-b상 campaign-owned = 정지 가능. 근거를 `probe/master-cleanup.txt`에 남기고 SIGTERM으로 정지한 뒤
규정 환경으로 재기동했다. 타 사용자 프로세스는 건드리지 않았다(프로브 기간 중 타 사용자 `cub_server`
부재 확인).

### 0-b. 도구 관련 기록

1차 기록은 `perf record --call-graph lbr`로 했으나 이 호스트 조합(perf 4.18 / kernel 6.9)에서 콜체인이
얕아 포괄(children) 귀속 최대치가 1.68%에 머물러 사용 불가였다. 따라서 동일 문장을
`--call-graph dwarf,2048 -F 99`로 재기록해 귀속에 사용했다(RelWithDebInfo `-g` 바이너리라 DWARF
언와인딩이 정확). 두 기록 모두 보존한다.

| 산출물 | sha256(앞 16) |
|---|---|
| `q15.dwarf.perf.data` | `81de5d817755b568` |
| `q18.dwarf.perf.data` | `3a7699a3bcf4467e` |
| `q15-trace.out` | `2d772f05247d1f5c` |
| `q18-trace.out` | `dfe4af21f99d2d55` |
| `q15body-trace.out` | `39a33fe1278366b8` |
| `q15diag.out` | `3276d40f03a1feef` |

## 1. 트레이스 결과 (SET TRACE ON, 각 질의 워밍업 1회 + 트레이스 1회)

### Q18 (관측 타깃) — traced wall 37.94 s

```
SCAN (table: dba.lineitem) (heap time: 11804..12054, parallel workers: 6, gather: mergeable list)
GROUPBY (time: 25768, hash: partial, sort: true, page: 266234, ioread: 147387, rows: 624)
        (parallel workers: 6, time: 666..699, page: 38245..43191, ioread: 4355..4758)
```

- `hash: partial` ⇒ `groupby_hash == HS_REJECT_ALL` (해시 포기). 소스 확인:
  `query_dump.c:3948-3950`, `:3350-3352`.
- GROUPBY 아래에 `parallel workers: 6` 서브라인이 **있다** ⇒ SORT_GROUP_BY 병렬 정렬이 한 번은
  발동했다. **단, 어느 정렬인지는 트레이스로 구분되지 않는다** — `gby_px.stats`와 `part_px.stats`가
  모두 같은 `&xasl->groupby_stats`를 가리키기 때문(`query_executor.c:5591`, `:5683`). §2가 이를 가른다.

### Q15 (1차 게이트 타깃) — traced wall 10.88 s

```
SCAN (table: dba.lineitem) (heap time: 2836..2857, parallel workers: 6, gather: mergeable list)
GROUPBY (time: 2523, hash: partial, sort: true, page: 17347, ioread: 12597, rows: 100000)
   ... (revenue0 뷰가 두 번 물질화됨)
GROUPBY (time: 2586, hash: partial, sort: true, page: 13787, ioread: 14971, rows: 100000)
```

- 두 GROUPBY 노드 모두 `hash: partial`(HS_REJECT_ALL) 이지만 **`parallel workers` 서브라인이 전혀 없다**
  ⇒ Q15의 group-by 폴백 정렬은 **IMP-015 바이너리에서도 완전 직렬**이다.
- view 부재/삭제 증명(§6-b): 실행 전 `db_class` count 0, 실행 후 0 (drop 완료).

### Q15 진단 보강 (원인 절단용, 추가 프로브 문장)

| 실험 | 입력 규모 | GROUPBY 결과 |
|---|---|---|
| 뷰 본문 단독 (3개월 창) `q15body-trace.out` | 2,265,714행 / sort page 18299 | **직렬** (parallel workers 없음) |
| 뷰 본문 12개월 창 `q15diag.out` | 9,123,688행 / sort page 85534 | **직렬** (parallel workers 없음) |

⇒ 크기 문턱(`sort_page_threshold` 2048) 때문이 아니고, 상위 질의 구조(SUBQUERY/ORDERBY 동시 예약)
때문도 아니다(단독 실행도 직렬). 해시 상태 때문도 아니다(`hash: partial` = HS_REJECT_ALL ⇒
`gby_px.hash_eligible = (1 && false) = 0` ⇒ `sort_check_parallelism`의 첫 게이트는 통과).

## 2. perf 귀속 — ② fan-in merge vs ③ finalize drain

방법: DWARF 콜체인 표본에서 **표본 하나의 콜체인에 특정 심볼이 등장하는지**로 셈
(`perf script` 스트리밍 + awk, 큰 파일은 읽지 않음). 원자료 `q15.chaincounts.txt`,
`q18.chaincounts.txt`; 포괄 비율표 `q15.phase-attrib.txt`, `q18.phase-attrib.txt`.

### Q18 (표본 10,684개)

| 심볼 (국면) | 표본 | 비율 |
|---|---|---|
| `sort_put_result_from_tmpfile` (**③ 병렬 drain**) | 716 | 6.70% |
| `sort_end_parallelism` (②+③ 컨테이너) | 716 | 6.70% |
| `sort_merge_nruns` (**② fan-in merge**, 워커 콜백) | 103 | 0.96% |
| `sort_exphase_merge` (**직렬** 병합/드레인) | 1,700 | 15.91% |
| `qexec_gby_put_next` (main group-by put_fn) | 1,203 | 11.26% |
| `qexec_hash_gby_put_next` (부분 해시리스트 정렬 put_fn) | 690 | 6.46% |
| ③ ∧ `qexec_gby_put_next` | **0** | 0.00% |
| ③ ∧ `qexec_hash_gby_put_next` | **688** | 6.44% |

포괄(children) 비율(`q18.phase-attrib.txt`): `sort_listfile` 21.02%, `sort_listfile_internal` 18.16%,
`sort_exphase_merge` 16.87%, `sort_end_parallelism` 7.21%, `sort_put_result_from_tmpfile` 7.21%,
`qexec_gby_put_next` 11.98%, `qexec_hash_gby_put_next` 6.95%, `qexec_hash_gby_agg_tuple` 39.39%,
`sort_listfile_execute` 3.72%, `qexec_groupby` 2.84%.

**해석 (결정적):**

1. ③ 병렬 drain 표본 716개 중 **688개가 `qexec_hash_gby_put_next`와 동시 출현**하고
   **`qexec_gby_put_next`와 동시 출현하는 표본은 0개**다. ⇒ Q18에서 병렬로 도는 SORT_GROUP_BY는
   **해시 부분리스트(partial hash list) 정렬**(IMP-015가 `part_px.hash_eligible = 0`으로 무조건
   병렬 적격화한 그 정렬)이고, **메인 group-by 폴백 정렬은 병렬이 아니다.**
2. 메인 group-by 정렬은 직렬 경로로 돈다: `sort_exphase_merge` 1,700 표본 아래에서
   `qexec_gby_put_next` 1,203 표본. `sort_put_result_from_tmpfile`와는 한 표본도 겹치지 않는다.
3. 그 유일한 병렬 인스턴스 안에서는 **③이 ②를 압도**한다: ③ 716 vs ② 103 →
   **③ / (②+③) = 87.4%**. spec D4의 "③ 지배" 가정은 (그 인스턴스에 한해) **확인**된다.

### Q15 (표본 5,088개)

| 심볼 | 표본 |
|---|---|
| `sort_listfile` | 480 |
| `sort_exphase_merge` (직렬 병합/드레인) | 379 |
| `qexec_gby_put_next` | 299 |
| `sort_put_result_from_tmpfile` (③) | **0** |
| `sort_end_parallelism` | **0** |
| `sort_merge_nruns` (②) | **0** |
| `qexec_hash_gby_put_next` | **0** |

포괄 비율(`q15.phase-attrib.txt`): `sort_listfile` 10.00%, `sort_exphase_merge` 8.24%,
`qexec_gby_put_next` 6.51%, `sort_inphase_sort` 2.41%, `qexec_groupby` 3.47%;
`sort_listfile_execute` / `sort_end_parallelism` / `sort_put_result_from_tmpfile` /
`qfile_sort_get_next_parallel` / `sort_merge_nruns` **전부 absent**.

**해석:** Q15에는 IMP-032가 공략하려는 국면 **②도 ③도 존재하지 않는다.** 병렬 폴백 정렬 기계장치가
한 번도 진입하지 않으며, 정렬 비용 전부(≈10% of 서버 cycles)가 고전적 직렬
`sort_inphase_sort` + `sort_exphase_merge` 경로에 있다. 부분 해시리스트 정렬도 없다(spill 없음 —
해시 **포기**만 있었고 **축출**은 없었다).

## 3. 기대효과 산정과 MDE 판정 (spec D1 규율)

산정 규율: "기대치는 **프로브로 측정된 리더 잔여 × 논증된 제거가능 분율(Amdahl)**로만 산출한다.
구 레짐 밴드·이종 경로 절대치의 이관은 금지."

### Q15 (1차 타깃, 게이트)

- 측정된 리더 잔여(②+③) = **0.00%** — 해당 국면이 실행되지 않는다(§2 Q15 표: ③ 0표본, ② 0표본,
  `sort_end_parallelism` 0표본).
- 따라서 제거가능 분율을 무엇으로 잡아도 **기대효과 = 0.00%**.
- MDE: §6-d-1 corrected MDE는 Q15에 대해 **존재하지 않는다**
  (`restart-variance-calibration.json`의 `queries_not_covered_at_all`에 Q15 포함; Phase 1A 미실행).
  IMP-015 §5와 동일한 **라벨링된 restart-regime 대체 MDE**를 쓰더라도 §6-d의 하한
  `MDE = max(1%, 2 × CV)` 때문에 **어떤 경우에도 ≥ 1%**다 (IMP-015가 Q10에 쓴 대체값은 1.42%).
- 판정: `기대효과 0.00% < MDE(≥1%)` ⇒ **`UNPROVABLE_ON_THIS_HOST`**.
  이 판정은 대체 MDE의 정확한 값에 의존하지 않는다 — 하한 1%만으로 결정된다.

### Q18 (관측 타깃, 게이트 아님)

- 병렬로 도는 정렬은 **부분 해시리스트 정렬**뿐이고, 그 안에서 ③ = 6.70% / ② = 0.96%
  (전 서버 cycles 기준, 포괄로는 ③ 7.21%). 즉 IMP-032식 ③ 병렬화의 이론적 표적은 Q18에서
  **전체의 7% 수준**이며, 그 대상 put_fn은 `qexec_gby_put_next`가 아니라
  **`qexec_hash_gby_put_next`** — spec D4가 기술한 대상(`qexec_gby_put_next`)이 아니다.
- wall 수준 기대효과 환산은 cumulative-phase telemetry pass 소관(spec §B 항목 5)이며 여기서
  단정하지 않는다. Q18은 게이트가 아니므로 판정에 사용하지 않는다.

## 4. 이 프로브가 확정한 것 / 확정하지 않은 것

확정:

1. Q15(게이트)와 Q18(관측) 모두에서 **메인 group-by 폴백 정렬은 IMP-015 하에서도 직렬**이다.
2. IMP-032가 정의한 표적(병렬 폴백 정렬의 리더 잔여 ②+③)은 **Q15에 존재하지 않는다** ⇒ Q15 기대효과 0
   ⇒ `UNPROVABLE_ON_THIS_HOST`.
3. Q18에서 병렬로 도는 유일한 SORT_GROUP_BY는 **해시 부분리스트 정렬**이며, 그 안에서는 ③이 ②를
   87.4 : 12.6으로 압도한다(spec D4의 "③ 지배" 가정은 그 인스턴스에 한해 확인).

확정하지 않음 (IMP-015 소관, IMP-032 스코프 밖):

4. **메인 group-by 정렬이 왜 병렬 게이트를 통과하지 못하는가.** 배제된 원인: (i) 입력 규모/페이지
   문턱(9.1M행·85,534 sort page에서도 직렬), (ii) 해시 상태(`hash: partial` = HS_REJECT_ALL이므로
   첫 게이트 통과), (iii) 상위 질의 구조(뷰 본문 단독 실행도 직렬). 남은 후보:
   `sort_check_parallelism`(`external_sort.c:5236-5246`)의 `input_list->page_cnt`가 gather된
   mergeable-list 입력에서 문턱 미달로 보이는 경우, `px->parallelism`(= `xasl->parallelism`) 힌트가
   해당 XASL 노드에서 `0 또는 1`이어서 `compute_parallel_degree`가 즉시 0을 돌려주는 경우
   (`px_parallel.cpp:128-131` "hint >= 0 and < start_degree disables parallel execution"),
   `try_reserve_workers` 실패. 단, 같은 문장 안에서 부분리스트 정렬은 병렬화됐으므로 힌트 후보는
   Q18 관측과 상충한다 — 확정에는 계측 빌드가 필요하고, 그것은 첫 소스 수정에 해당하므로 정지 상태에서
   수행하지 않았다.

## §8-c 상태 블록

```yaml
TPCH_SSPQ_IMPL_STATUS:
  campaign_id: tpch-sspq-impl-r1-20260803
  imp_id: IMP-032
  impl_ssot_commit: 276d8e866f0f4702648ccb9b8c00c8c5410931e9
  impl_ssot_blob_sha: 15b42ddca521444fa54b34b0fa8477ed2df643f6
  session_id: 019fc85d-8da5-7000-bc9e-7f97de474072
  stage: G004-D1-attribution-probe-complete
  state: blocked
  branch: impl/tpch-sspq-impl-r1-20260803/IMP-032-gby-parallel-finalize
  report_commit: null
  verdict: null
  artifact_fingerprint: q15.dwarf.perf.data=81de5d817755b568, q18.dwarf.perf.data=3a7699a3bcf4467e
  timestamp: 2026-08-04T02:10:00+09:00
  next_action: 사용자 결정 대기 — (A) 스코프 재설계(px_scan식 XASL 복제) / (B) ② merge 피벗 / (C) 부분 직렬화 / (D) 연기·기각 / (E) 신규: 메인 group-by 정렬의 병렬 게이트 미진입 원인 규명(IMP-015 후속)
  blocker: |
    두 개의 독립 정지 조건이 동시에 성립.
    (1) spec §A A3 반증 (GROUPBY_STATE 워커별 복제 불가) — stop-and-report, 스코프 재설계는 사용자 결정.
    (2) spec D1 UNPROVABLE_ON_THIS_HOST — Q15 기대효과 0.00% < MDE 하한 1%. Q15의 group-by
        폴백 정렬이 IMP-015 하에서도 완전 직렬이어서 IMP-032의 표적 국면(②+③)이 실행되지 않는다.
  source_modified: none (worktrees/IMP-032 clean at 61f4b4cf9)
```
