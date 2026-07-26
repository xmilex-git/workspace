# PR #7504 최소 브랜치 성능 게이트 재집행 (2026-07-25, 확정 — 재게이트 PASS · 로컬 merge 완료)

**결론: 07-24 게이트 FAIL은 검정력 부재로 무효, 동일 기준 16쌍 재게이트는 PASS(paired median
−0.19%, CI 상한 +2.28%), 작업량은 head/base = 1.0000. 계약대로 r304 WIP에 `--ff-only` merge하고,
주석/스타일 정리 후 `xmilex/bulkidx/noredo-parallel-r304-wip`에 `3ffeab793..9dd0f4f25`
fast-forward push 완료(2026-07-26).**

이슈 #164 "남은 것 1·2"(성능 회귀 커밋 단위 귀속 / merge 재결정)의 후속. 원격(192.168.6.33)
귀속 캠페인은 안전계약 위반으로 중단된 상태이므로 **로컬 자산만으로** 판정했다. 새 빌드·새 픽스처·
권한상승·원격 접속 없음.

## 1. 07-24 성능 게이트는 검정력이 없어 merge 재결정의 근거가 될 수 없다 (확정)

`evidence/perf-min-gate-20260724-173502/measurements.tsv`의 valid 8쌍을 재분석했다.

| 항목 | 값 |
|---|---|
| base(3ffeab793) valid 8런 | 101.6 130.3 105.9 105.4 115.2 106.7 111.9 101.7 s |
| head(12de99b47) valid 8런 | 106.2 178.5 121.1 104.3 103.3 113.1 113.8 104.5 s |
| paired deltas | +4.56 +36.97 +14.42 −1.05 −10.35 +6.05 +1.68 +2.75 % |
| per-run CoV | base **8.7%**, head **21.3%** |
| paired delta sd | **14.00 pp** |
| paired median 부트스트랩 95% CI | **−1.05% .. +14.42%** (0 포함) |
| paired mean 95% CI (t, n=8) | −4.83% .. +18.59% |

- 사전 고정 기준의 세 축(paired median ≤+3%, aggregate median ≤+3%, head 패배 <6/8)은
  **관측 분산 대비 마진이 1/5 수준**이라 참 효과가 0이어도 위반되기 쉽다.
  패배축 단독으로 `P(head 패배 ≥ 6/8 | 참 차이 0) = 0.145`.
- 같은 분산에서 3pp를 80% 검정력·양측 5%로 판별하려면 **약 171쌍**(≈20시간)이 필요하다.
  즉 07-24 게이트는 "+3% 회귀"를 검출한 것이 아니라 **판별 불능 구간에서 FAIL 쪽으로 떨어진 것**이다.
- 따라서 **FAIL 판정 자체는 계약대로 유지**(merge 보류 유지)하되, 그 FAIL을 "회귀 실재"의
  증거로 쓰는 것은 무효다. 커밋 단위 귀속을 이 FAIL 위에 올려 세우면 존재하지 않을 수 있는
  효과를 추적하는 것이 된다 — 원격 귀속 캠페인이 4쌍에서 "드리프트가 바이너리 델타를 압도"로
  끝난 것과 정확히 같은 실패 양상이다(`final-chain-status.txt`의 attr 기록).

## 2. 코드측 귀속: 최소 4커밋 중 측정 경로에 per-row/per-page 작업을 추가한 것은 없다 (확정)

측정 워크로드 = `parallelism=32`, `max_parallel_workers=100`, `parallel_sort_page_threshold=0`에서
`loaddb -C -i "CREATE INDEX idx_t20g_k ON t20g(k)"` (t20g 341,000,000행) — 즉 **병렬 shard 빌드**.

| 커밋 | 런타임 델타 | 측정 워크로드에서의 실행 횟수 |
|---|---|---|
| `c448b3a2e` P1 safety | ① `sbtree_load_index` optional-tail 경계 비교 ② 빌드 종료 시 `log_append_redo_data`→`log_append_postpone` 1건 ③ `LOG_IS_*` 매크로에 정수 비교 1개(`RVBT_BULK_BUILD_COMMITTED`) 추가 ④ `log_recovery.c` 함수(복구 전용) | ①② **빌드당 1회** ③ log append당 정수 비교 1개(측정 불가 수준) ④ **0회**(정상 실행에 복구 경로 없음) |
| `278a2d283` 2-core degree | `compute_parallel_degree`의 공통 게이트에 `type != INDEX_BUILD &&` 술어 추가 | 빌드당 1회. 본 호스트는 `system_core_count=32`이므로 `32 <= 2`가 양쪽 모두 false — **결과·경로 완전 동일**(inert) |
| `dc22f2228` vacuum 직접 append | `worker_idx < 0`일 때 notify를 큐 대신 직접 append | **0회.** 병렬 빌드에서 put은 shard worker(`worker_idx >= 0`)가 수행 → 기존 증거로 실증: `evidence/addendum-min-20260724-172352/vnprobe.out` = `v2-parallel (direct=0 drain=50000)`. 게다가 이 분기는 notifiable 행(MVCC delid valid 또는 insid not-all-visible)만 진입 — 픽스처는 07-23 적재 후 동시 리더 없음 |
| `12de99b47` sysop 수명 | `log_sysop_attach_to_outer()` 호출을 provider open + shard 준비 **뒤로 이동**, 실패시 부모 sysop abort | 빌드당 1회(attach 지점 이동). provider의 span sysop이 부모에 붙는 것도 span 수(수십) 만큼의 O(1) 리스트 splice — per-row/per-page 작업 증가 없음 |

hot scan/merge/put 루프의 코드 델타는 0이다(diff 9파일 +154/-37 전량 확인). 즉 **+3% 규모의
구조적 회귀를 만들 코드 경로가 존재하지 않는다** — 07-24의 FAIL이 노이즈라는 §1의 통계적 결론과
독립적으로 일치한다.

## 3. 측정 레짐 발견 — 이 픽스처의 wall-clock은 "쓰기 흡수 vs 디스크" 레짐에 지배된다

기준을 완화해 PASS를 만드는 것은 골포스트 이동이므로 하지 않았다. 07-24의 세 축을 **필요조건으로
그대로 유지**하고 "긍정 판정은 검정력을 요구한다"는 조건(S1: paired median 부트스트랩 95% CI
상한 ≤ +3%)만 추가한 뒤 분산 통제를 시도했다. 그 과정에서 07-24 게이트의 8.7% CoV의 실제 원인이
드러났다.

### 3.1 폐기된 시도 — prewarm (`perf-min-regate-20260725-134746-ABORTED-protocol-defect`)
데이터 볼륨 22.9GiB를 캠페인 시작 시 page cache에 올려 "런마다 heap 캐시 잔존율이 다른" 분산원을
없애려 했다. 결과는 반대였다: 동일 워크로드가 **110s → 365s**, `cub_server` 실기록이
**약 1.2GB → 119GB**로 전환됐다. 정렬 temp 볼륨 수십 GB는 캐시 여유가 있으면 대부분 writeback
없이 unlink로 사라지는데, 캐시를 선점하면 전량 디스크로 나간다. **판정 산출 전에** 프로토콜 결함으로
중단하고 warmup 2런을 증거로 보존했다(사후 기준 변경 아님).

### 3.2 레짐은 prewarm 없이도 이미 바뀌어 있었다 (07-24 대비)
prewarm을 끄고 재측정해도 런 시간은 350~380s였다. 항상 켜져 있는 page-buffer victim flush
NOTIFICATION(계측 오버헤드 0)을 07-24 서버 err 로그와 대조하면 워크로드 자체가 커졌다:

| 지표 (런당) | 07-24 게이트 | 07-25 |
|---|---|---|
| 서버가 볼륨으로 내려보낸 페이지 | 6,126,xxx (**93.5 GB**) | 10,086,xxx (**153.9 GB**) |
| victim flush 사이클 | 11.3k (사이클당 543p) | 122k (사이클당 83p) |
| log archive roll | 약 0.3회 | 8회 |
| `cub_server` 실기록(측정) | (미기록) | 107~118 GB |
| 디스크 상태 | — | `sda` %util 98%, 443 MB/s 포화 |

즉 07-24도 07-25도 **디스크 쓰기 대역이 병목**이며, 07-24는 쓰기의 상당 부분이 page cache에서
흡수·소멸됐고 07-25는 그렇지 않다. 07-24 게이트의 per-run 8.7% CoV와 178.5s 이상치는 이
"흡수되느냐" 경계에서의 요동으로 설명된다 — 코드가 아니라 **캐시 여유가 지배 변수**다.
레짐 변화의 원인은 픽스처 누적 상태(20+회 create/drop 이후의 로그·vacuum 백로그)로 추정하며,
두 레인에 대칭이므로 A/B 비교의 공정성에는 영향이 없다(순서균형 유지). **07-24 수치와 07-25
수치의 풀링은 금지**한다.

## 4. 결과 (1) — 작업량 대조: head는 base보다 더 많은 일을 하지 않는다 (확정)

`evidence/perf-min-counters-20260725-141031` (사전 등록 후 실행, warmup 1런/레인 제외,
ABBA 순서균형 valid 4쌍, 전 런 rc=0 · idx_exists=1):

| 지표 (valid 4런 중앙값) | base(3ffeab793) | head(12de99b47) | head/base |
|---|---|---|---|
| timed 구간 서버 flush 페이지 | 10,066,507 | 10,085,978 | **1.0019** |
| `cub_server` 실기록 MB | 116,218 | 114,511 | **0.9853** |
| wall-clock 중앙값 | 368.07 s | 366.63 s | 0.9961 |
| flush 사이클 수 | 120,590 | 127,554 | 1.0577 |

- **작업량 판정: 추가 작업량 없음.** 사전 등록 기준(모든 work counter 비율 ≤ 1.01)을 만족한다.
  레인 내 런간 변동도 ±0.4%로 0.19% 차이는 그 안에 있고, 실기록은 head가 오히려 1.5% 적다.
- flush 사이클만 +5.8%인데 페이지 수는 동일하다 — 같은 양을 더 잘게 나눠 내보낸 것(플러셔 배칭
  차이)이며 작업량 증가가 아니다.
- wall-clock(2차 기록): paired deltas +1.91 / +0.94 / −1.90 / +1.12 %, paired median **+1.03%**,
  aggregate median **−0.39%**, per-run CoV **2.7% / 2.7%**, paired sd **1.67pp**,
  부트스트랩 95% CI **−1.90% .. +1.91%**. n=4이므로 정식 판정은 내리지 않았다(P3 축은 n=4에서
  귀무가설 하 P(≥3/4)=0.31로 무의미).
- **부수 확정: 이 레짐의 재현성은 07-24보다 8배 좋다**(paired sd 1.67pp vs 14.00pp).
  따라서 3pp 마진은 **16쌍으로 판별 가능**하다 — 07-24 프로토콜에서 필요했던 ~171쌍이 아니다.
- 하네스 한계 기록: `cubrid statdump`의 `Num_*` 카운터는 perfmon watcher가 붙어 있을 때만
  누적된다(`perfmon_add_stat` → `perfmon_is_perf_tracking`). watcher 없이 뜬 서버에서는 전부 0이라
  작업량 지표로 쓸 수 없다. 대신 항상 기록되는 victim flush NOTIFICATION을 timed 창구간으로
  집계했다(`harness/analyze-flushwork.py`).

## 5. 결과 (2) — 재게이트 #2 (16쌍, 07-24 기준 3축 그대로)

- 사전 등록: `evidence/perf-min-regate2-20260725-153225/gate-manifest.txt`
  (러너·판정기 sha256 동봉, 결과 취득 전 작성 → 완료 후 VERDICT 블록 append). 레인 바이너리는
  07-24 게이트와 **동일 파일**(`a90373a0…` / `ffaabf65…`, 재빌드 없음).
- 프로토콜: `measure-pairs-v2.sh PREWARM=0` — 런마다 stop → start → DROP INDEX(untimed) →
  `sync` + Dirty≤256MB 하강 대기 → timed CREATE INDEX → timed 밖 `idx_exists` assert,
  공변량 런별 기록. warmup AB+BA 제외 + valid **16쌍** 순서균형(15:32~19:38 KST).
- 판정 기준: P1 paired median ≤+3% / P2 aggregate median ≤+3% / P3 head 패배 <12/16 /
  S1 부트스트랩 95% CI 상한 ≤+3%. PASS는 네 조건 모두 충족일 때만.

### 5.1 결과 — **PASS** (네 축 전부 충족, 무효 런 0)

| 축 | 값 | 기준 | 판정 |
|---|---|---|---|
| P1 paired median | **−0.19%** | ≤ +3% | ok |
| P2 aggregate median | **+0.49%** | ≤ +3% | ok |
| P3 head 패배 | **7/16** | < 12/16 | ok |
| S1 부트스트랩 95% CI | **−2.78% .. +2.28%** | 상한 ≤ +3% | ok |

- paired deltas(%): −0.91 −2.78 −3.77 +2.28 −3.63 +0.85 +3.16 −5.38 −0.25 +0.35 +3.16 −0.14 −1.51 +3.43 +4.54 −4.83
- per-run CoV base **2.6%** / head **2.8%**, paired sd 3.13pp. 전 36런 `rc=0 AND idx_exists=1`.
- 정합: 최종 픽스처 341,000,000행 · min 1 · max 341,000,000, release `checkdb -S` **rc=0**.

### 5.2 작업량 대조 (16쌍, timed 창구간 집계) — 동일

| 지표 (valid 16런 중앙값) | base | head | head/base |
|---|---|---|---|
| 서버 flush 페이지 | 10,086,169.5 | 10,086,231.5 | **1.0000** (62p/10.09M = 0.0006%) |
| `cub_server` 실기록 MB | 114,144.5 | 114,232.0 | 1.0008 |
| flush 사이클 | 125,443 | 126,783 | 1.0107 (배칭 차이 — 페이지 수는 동일) |

## 6. 결정 — merge 수행 후 **2026-07-26 스타일 정리 + push 완료**

사전 고정 계약("성능 게이트 PASS일 때만 r304 WIP에 `--ff-only` merge")대로 07-25에 로컬 merge하고,
07-26에 코드 스타일·주석 정리를 거쳐 원격에 push했다.

### 6.1 push 전 스타일 정리 (주석/문구만, 동작 불변)

외부 독자에게 이 변경은 **CBRD-27071 하나**여야 하므로, 내부 문서·프로세스 흔적을 걷어내고 장황한
주석을 줄였다. 커밋 4개를 rebase로 다시 쓴 결과 **9파일 +130/-36** (기존 +154/-37).

| 파일 | 정리 내용 |
|---|---|
| `log_recovery.c` | `see the CBRD-27071 ADR` 문구 삭제(리포에 없는 문서 참조), 파일-정적 플래그·함수 헤더 주석 4줄→2줄, `log_recovery ()` 종료 직전 무의미 공백줄 제거 |
| `external_sort.c` | 6줄 주석→3줄, cleanup 경로의 **죽은 대입**(`file_sysop_open = false;` 직후 return) 삭제 |
| `btree_load.c` | durability barrier 설명 9줄→4줄, vacuum 직접 append 주석 4줄→3줄 |
| `px_parallel.cpp` / `network_interface_sr.cpp` | 각각 4줄→2줄, 3줄→2줄 |
| 커밋 메시지 | `Review blocking fixes for…` → `Two fixes for…` (프로세스 언급 제거). 나머지 3개는 그대로 |

`CBRD-27071` 태그 자체는 코드베이스 관용(주석 내 `CBRD-xxxxx` 71곳)이라 유지했다.
검사: 추가 라인 중 120열 초과 0, 트레일링 공백 0, 내부 용어(campaign/evidence/ADR/workspace/issue) 0.

### 6.2 게이트 바이너리와의 차이 및 재검증

`git diff 12de99b47 9dd0f4f25`의 **비주석 변경은 죽은 대입 1줄 삭제뿐**이다. 그래도 재검증했다.

- release 풀빌드 rc=0 · optdebug 풀빌드 rc=0 (`11.5.0.2416-9dd0f4f`), 변경 파일발 **신규 경고 0**
  (남은 9건은 전부 무관 파일의 기존 `-Wmaybe-uninitialized`)
- optdebug `od-smoke` 3레인 PASS (병렬 10k / 함수 인덱스 10k / 직렬 강등 100)
- release TC 3종 PASS: `tc-replay-barrier`(restoredb 거부 경로 = 재작성한 복구 함수 직접 커버),
  `tc-loaddb-basic`, `tc-crash-restart`

### 6.3 push 결과

- 재작성 SHA: `3ffeab793` + `8e31d4879` → `c975214d0` → `4196e11d0` → **`9dd0f4f25`**
  (구 `c448b3a2e`/`278a2d283`/`dc22f2228`/`12de99b47`)
- `xmilex/bulkidx/noredo-parallel-r304-wip`: `3ffeab793..9dd0f4f25` **fast-forward push 완료**
  (upstream `CUBRID/cubrid`에는 push하지 않음 — remote push URL이 차단되어 있다)
- 백업 ref 전부 생존: `pr-7504-redesign`(68945f328), `backup/pr-7504-redesign-final`,
  `backup/pr-7504-redesign-20260724`, 태그 `backup-pr7504-pre-reorg`. 구 tip `12de99b47`도 로컬 유지.

근거 3중:
1. **07-24 FAIL은 무효**(§1) — 검정력 없음. merge 보류의 근거였을 뿐 회귀 실재의 근거가 아니다.
2. **재게이트 PASS**(§5.1) — 07-24와 동일한 3축을 유지한 채 검정력 있는 16쌍에서 통과, CI 상한 +2.28%.
3. **작업량 동일 + hot path 델타 0**(§2, §5.2) — 서버가 내려보낸 페이지가 0.0006% 차이.

### 6.1 승계 — 이슈 #164 "남은 것" 갱신

- **1. 커밋 단위 귀속**: 귀속 대상 효과가 존재하지 않는다(§1·§2·§5). **불필요로 종결.**
  원격(192.168.6.33) 캠페인은 재개하지 않았고 안전계약 재합의도 불필요해졌다.
- **2. merge 재결정**: 완료 — 로컬 ff-only merge 후 스타일 정리, 원격 push까지 완료(§6).
- **3. 원격 잔재 정리**: 미착수(사용자 지시 대기 — `perf20gattr`의 t10g, `~/bkx-attr/*`).
- **4. JIRA 첨부**: 미착수(수동). 번들은 최소 브랜치 기준 개정 검토 필요.