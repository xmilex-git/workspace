# bulkidx 세션 보고 (2026-07-18, 2차) — 1위 병목(머지 직렬화) 해소: B5 merge fusion

대상 브랜치: `bulkidx/noredo-parallel-r304-wip` (worktree `/home/cubrid/dev/worktrees/r304-bulkidx`).
신규 커밋 1건 `82f2d7639` (release+debug 빌드 green, push 0회). 증거: `.not_git_tracking/bulk_index_build/artifacts/u-g008/vtune-5g/` (measurements-20g-b5.tsv, b5ab-* 샘플러, smoke-b5-*).

## 1. 지시와 처리

- **1위(최종 k-way 머지 직렬화) 개선** → B5 구현·검증 완료 (본 보고).
- **2·3위 기록만** → `.not_git_tracking/bulk_index_build/perf-followups.md`에 코드 위치·신호·개선안 기록.

## 2. 병목과 해법

**병목(VTune b4fix 20G 캡처 + 네이티브 타임라인)**: 병렬 빌드는 워커 run 32개를
그리디 4-way 큐(`SORT_PX_MERGE_FILES=4`, 32→8→2→1)로 **하나의 최종 run으로 물질화**한 뒤에야
shard 분할·병렬 put을 시작. 레벨마다 전 데이터(~22.5GB)를 재기록하고 트리 꼬리는 1-2 스레드로
좁아져 **빌드의 ~54%(≈350s/645s)가 사실상 단일 스레드 + 동기 temp I/O**. 병렬 put은 남은 ~17%
구간에만 작용했다.

**B5 (`82f2d7639`, external_sort.c +640/−127)**: fan-in 머지를 통째로 생략.
- pilot(최대) run에서 page-비례 위치의 **키그룹 시작**으로 splitter 키 선정
  (`sort_px_select_splitters`) — 기존 splitter의 "중복키 그룹 불분할" 불변식을 키 비교
  기반으로 전역화(< / >= splitter 분할이라 그룹 분할 원천 불가).
- run마다 splitter를 page+slot 이진탐색(`sort_px_run_lower_bound`)해 shard별
  [start,end) 슬라이스 산출(`sort_px_slice_runs_index_leaf`).
- 각 shard 워커가 자기 슬라이스들을 **min-heap k-way 머지하며 즉시 put**
  (`sort_put_result_index_leaf`). 비교자는 sort 자체의 cmp_fn(= (key,OID) 엄격 전순서)이라
  머지 출력이 기존 최종 run의 해당 구간과 **바이트 동일 시퀀스** — 의미 변화 0.
  REC_BIGONE은 exphase 머지와 동일한 grow-and-reuse 검색 규약.
- NOT_ATTEMPTED(직렬/1샤드/빈 입력) 시 레거시(단일 run 머지+직렬 put) 폴백 유지.
  성공 시 initial run temp는 caller가 명시 반납. 사어가 된 단일-run splitter와
  `px_index_shard` 배관은 제거.

## 3. 결과

### 20GB 결정 측정 (campaign convention, cold restart, 교대, warmup1+valid3, 8/8 rc=0)

| binary | valid (s) | median |
|---|---|---|
| develop | 598.2 / 644.5 / 679.9 | 644.5 |
| **B5** | 167.5 / 171.7 / 195.8 | **171.7** |

**develop 병렬 대비 3.75×** (수정 전 branch +13.6% 느림 → B4 +3.7% 빠름 → B5 3.75×).
5G fixture: 31.7s (B4 75~90s). 스레드 타임라인(1Hz /proc): 빌드 전 구간 멀티스레드,
1-2스레드 머지 밸리 소멸(`log/b5ab-b5fix-valid-3-sampler.tsv`).

### 정합성

- 20G: 양끝 키 점조회 정확히 3,410행(=341M/100k), COUNT 341,000,000,
  **COUNT(DISTINCT k)=100,000(인덱스 전체 순서 순회)**, MIN/MAX 정상.
- 5G: 동일 오라클 green(850/키, 85M, 100k distinct) + 빌드 내 seam 키순서 검사(green 아니면 빌드 실패).
- `checkdb -S -I idx_t5g_k`(85M행, B5 산출 인덱스) **완주 — 불일치 보고 0건**(`log/checkdb-b5-5g.out` 0바이트, 정상 시그니처).

## 4. 정직 기록 / 한계

- mini 테이블(1.6M)의 `DEBUG_BTREE: px construct` 라인 채증은 param 미적용으로 실패 —
  엔게이지먼트는 시간(레거시 폴백이면 ≥90s/5G, 실측 31.7s)·rc=0·오라클·타임라인으로 입증.
- splitter는 pilot run 비례 위치 기반이라 극단 skew 시 shard 불균형 가능(최악도 현행 직렬
  꼬리보다 나쁠 수 없음). 20G dev CoV 6.4%는 세션 간 정상 변동 범위.
- 캠페인 재검증 매트릭스(L1/L2/L4/L6/L7b/kill-switch/killsweep) 편입은 B4·B5 묶음으로 필요 —
  push 전 필수 게이트로 남김.

## 5. 상태

- worktree HEAD `82f2d7639` (B4 `d8f6b3918` 위), push 안 함. 빌드: release
  `/home/cubrid/release/CUBRID-b5merge-matrix-local`, debug 게이트 green.
- 서버/포트/스트레이 마스터 정리 완료. checkdb 완료.
- 다음 후보: ① followups 2위(find_nth 캐시)·3위(victim 카운터) ② overflow-key workload
  (VARCHAR 2100) 8M 매트릭스 재측정 ③ 원격 전용 레인(backup-overlap/L6/L7b) 재봉인.

## 6. 후속 완료 (같은 날, 보스 지시)

- **재검증 매트릭스 재수행 (로컬, harness-v3 규율: 타이트 t_budget·TIER-A/B 소형·release 우선·debug 미사용)** —
  전 레인 PASS: U-OV3 9/9(conf 3변형×3), L2 killsweep K1~K5×2 10/10(release-diag, 훅 클린적용→빌드→원복),
  kill-switch 4조합, empty/1행(B5 폴백 에지), 직렬 경로, crash-restart 5/5(0.5s 완주로 post-commit
  내구성 판정), U-MARKER-MICRO(sticky-root VPID 일치). 하네스 결함 2건(master auto-restart 오염,
  USING INDEX 구문) 수정 후 재실행 — 제품 결함 0건, debug 재현 불요.
  증거: `artifacts/u-g008/matrix-b5/SUMMARY.md` (+evidence 1.9MB). 픽스처 DB deletedb 완료.
- **push**: `xmilex/bulkidx/noredo-parallel-r304-wip` `3ebe17eb9..82f2d7639` (B2-01/02·B2-S1·style·B3·PGBUF·B4·B5 스택).
- **JIRA CBRD-27071**: Description 갱신(20GB 3.75× 수치, B4/B5 반영 구현 설명) + 코멘트 4775273 게시
  (원인 2건·재측정·매트릭스 요약·브랜치 82f2d7639 링크). 초안: `.git_ignored_dir/jira/CBRD-27071/`.
