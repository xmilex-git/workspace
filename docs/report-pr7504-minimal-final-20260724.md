> **[SUPERSEDED 2026-07-25 — 성능 게이트 부분]** 아래 §2·§3의 "성능 게이트 FAIL / merge 보류"는
> `docs/report-pr7504-perf-regate-20260725.md`로 대체됐다. 07-24 게이트는 검정력 부재(per-run
> CoV 8.7%, paired sd 14.0pp, paired median 95% CI −1.05%..+14.42%)로 무효 판정됐고, 동일 3축을
> 유지한 16쌍 재게이트는 **PASS**(paired median −0.19%, aggregate +0.49%, 패배 7/16, CI 상한
> +2.28%) + 작업량 동일(서버 flush 페이지 head/base = 1.0000). 계약대로 로컬
> `bulkidx/noredo-parallel-r304-wip`에 `--ff-only` merge 완료(3ffeab793 → 12de99b47, push 없음).
> **기능 배터리 PASS 등 나머지 절은 유효하다.**

# PR #7504 최소 브랜치 최종 보고 (2026-07-24, 확정 — 배터리 PASS · 성능 게이트 FAIL · merge 보류)

**결론: 기능 배터리 전체 PASS, 성능 게이트는 사전 고정 기준 3축 모두 위반으로 FAIL ⇒ 계약대로 r304 WIP merge 하지 않음(push 없음). r304 WIP은 `3ffeab793` 그대로.**

## 1. 현재 상태
- 브랜치 **`pr-7504-minimal`** = 정확히 `3ffeab793`(원 PR 헤드) + 커밋 4개, HEAD **`12de99b47`** (push 안 함):
  1. `c448b3a2e` — P1 safety blockers: protocol optional-tail 가드(UB-free 정수 오프셋) + rollback-safe commit-time postpone barrier(DURABLE/COMMITTED 2-rcvindex, media replay refuse) — 실증 blocker 2건의 유지분
  2. `278a2d283` — 2-core degree hunk: `compute_parallel_degree` 공통 2코어 게이트에서 INDEX_BUILD 제외(+5/-1, 단일 파일) — JIRA degree≥2 요구
  3. `dc22f2228` — vacuum 알림 트랜잭션 스레드 직접 append 복원(+12) — **예외 조항 발동**: 원 PR이 develop의 직접 append를 전 경로 64MiB 큐로 대체(diff 증명: e8b961468=직접/큐 0흔적 → 3ffeab793=큐 11흔적) → long reader 하 직렬 CREATE INDEX 기능 회귀. 큐·상한은 tdes 공유 제약이 실재하는 shard worker 전용으로 축소
  4. `12de99b47` — index-file sysop을 전 shard 자원 준비 완료까지 유지(+30/-9) — **예외 조항 발동**: 원 PR이 provider/shard 준비 "이전"에 attach_to_outer(diff 증명: attach/provider 패턴 develop 0흔적) → 준비 실패 시 파일 회수가 클라이언트 abort에 전적 의존. 실패 시 부모 sysop abort로 파일·스팬 일괄 회수, `file_sysop_open` bool로 post-attach 중복 abort 차단
- **총 diff vs 원 PR: 9파일 +154/-37** (재설계 +1313/-606의 약 1/8). hot scan/merge/put 루프 변경 0 — 커밋 3·4는 빌드당 상수 횟수 경로.
- 계획 대비 편차 기록: 목표는 논리 커밋 2개였으나, 리뷰 예외 조항("원 PR이 새로 악화한 hunk가 diff로 증명되면 보고 후 수정")에 따라 사용자 지시로 3·4가 추가됨. C-slice/OOM 이식·px_sort_param 가드는 develop 기존 코드로 판명되어 **scope creep으로 제외**(착수분 원복).
- 참조 보존: `pr-7504-redesign`=68945f328(불변), `backup/pr-7504-redesign-final`, `backup/pr-7504-redesign-20260724`, 태그 `backup-pr7504-pre-reorg` 전부 생존.

## 2. 검증 현황
### 확보 (V5 = provenance-min-20260724-163254, HEAD 12de99b47 fresh build SHA 결속)
r4 abort-class(restoredb rc=0 + idx 부재) · tc 3종(replay-barrier/loaddb-basic/crash-restart) · compat 구(2320)→신(**행동 증거 한정**: loaddb rc=0 + idx_exists=1) · 2-core · 매트릭스 11셀 · ext-lanes E1~E7 · crash-window W0/W1/W2 — 전부 PASS.
**증거 유효성 규칙**: 로그 덤프 유틸 유래 수치(marker/copypage/notify 계수)는 캠페인 전체에서 **INADMISSIBLE** — V5 재사용은 SQL/restore/checkdb 행동 증거만 유효(사용자 계약: SSOT §3 규칙10 + harness-v3 TIER 규율, 이후 전 캠페인 0회로 강화).

### 확정 — addendum-min v5 **PASS** (`addendum-min-20260724-172352`, ADDENDUM_MIN_OK)
로그 덤프 0회 설계(P0×4·P1×5 반영, rg 금지토큰 0 + bash -n 증명). 결과:
- restart-forward PASS: W1 사망 + pre-crash marker=0 → recovery marker 정확히 1 + idx=1/iscan=50000/release checkdb rc=0
- FI provider/shard PASS: inject rc=3 + idx absent + retry scan 50000
- od-scale attestation normal/lower 각 정확히 1 → optdebug 빌드 rc=0 + od-smoke PASS(SQL-only)
- vacuum V1 direct=1000/drain=0, V2 drain=50000/direct=0 — 분기 배타성+완전성 PASS
- 선행 3회 런은 **하네스/환경 실패**로 보존(제품 실패 아님): ①전역 pgrep zombie 오집계 ②훅 abort() 종료 미보장→`_exit(86)` 교체 ③master `auto_restart_server` 즉시 재기동→RF lane에 `auto_restart_server=no` 명시. EV: 171326/171638/171928.
원 설계 명세:
- restart-forward: W1(`BKX_CRASH_AFTER_CWP`) 사망 + pre-crash marker trace=0 → env 없는 재기동에서 recovery marker trace **정확히 1** + idx/iscan/release checkdb
- FI provider/shard: 주입 실패 + 서버 생존 + index absent + 재시도 + checkdb (v8 훅)
- od-scale attestation(HINST 트레이스로 10k 발화 실증) → optdebug 빌드 + od-smoke(SQL-only, checkdb 없음)
- vacuum V1/V2: test-only bounded 트레이스(≤350KB)로 direct/drain 분기 배타성+완전성
- 안전장치: 금지토큰 preflight·df preflight·20MB/디스크 watchdog·top-level cleanup trap

### 확정 — 성능 게이트 **FAIL** (`evidence/perf-min-gate-20260724-173502`)
base=`3ffeab793` **fresh build**(`CUBRID-pr7504-base-gate`, r304 워크트리 HEAD 결속) vs minimal=`12de99b47`(V5 libcubrid SHA 결속), 동일 perf20gtip(341M행 실측)·conf, warmup AB+BA 각 1쌍(통계 제외) + valid 8쌍 순서균형, 각 run rc=0 AND idx_exists=1(카탈로그 assert, timed 밖).
**사전 고정 non-inferiority**: paired/aggregate median ≤ +3% AND head 패배 < 6/8.
- paired deltas: +4.56 / +36.97 / +14.42 / −1.05 / −10.35 / +6.05 / +1.68 / +2.75 (%)
- paired median **+3.66%** (>3% 위반) · aggregate median **+3.21%** (>3% 위반) · head 패배 **6/8** (<6 위반)
- ⇒ **FAIL — merge 금지.** 관찰: pair2 head 178.5s 이상치가 존재하나 사전 기준에 이상치 제외 조항이 없어 판정에 반영하지 않음(이상치 제외 시에도 paired median +2.75%로 경계선). 원인 분석: 회귀 폭이 세션 간 드리프트(±10%)와 동급으로 마진이며, 6/8 패배 패턴은 minimal 4커밋 중 hot-path 변경이 없다는 점에서 특정 커밋 귀속 불가 — 재현·귀속에는 추가 쌍 또는 커밋 단위 게이트가 필요.

## 3. merge 결정 — **하지 않음** (게이트 FAIL)
계약: 성능 게이트 통과 시에만 로컬 `bulkidx/noredo-parallel-r304-wip`에 `--ff-only` merge. 게이트 FAIL이므로 merge하지 않았고 r304 워크트리는 `3ffeab793` 그대로다(감사 확인). `pr-7504-minimal`(12de99b47)은 브랜치로 보존 — 성능 재게이트(추가 쌍/커밋 귀속) 후 재결정 가능. **push 없음.**

## 4. Full redesign — rejected experiment 기록
- 산출: `pr-7504-redesign` 68945f328(논리 7커밋), 원 PR 위 **+1313/-606**(전체 PR 순증 3176→3883, +22.3%) — "변경 최소화" 목표 미달이 기각 사유의 핵심. 성능 게이트도 미확정(마지막 순서균형 8쌍 +7.0%/2승6패, 귀속 4쌍은 median +1.8%·2승2패로 드리프트 지배 판정 — HOLD인 채 종료).
- 기술적 성과(후속 PR 후보로 유효): sorter↔loader 6-op 경계 계약(외부 심볼 0), 공용 record packer, 함수 인덱스 clone-lifetime 수정(UAR 크래시 실증·수정), STL bad_alloc 계약 갭의 C-슬라이스 해소, sort_listfile OOM cleanup 가드, 순수 술어(`log_is_system_op_started`) — 검증 자산(provenance 13레인+매트릭스 17셀+E1~E7, exact-HEAD SHA 결속)은 evidence 디렉토리에 보존.
- 이 중 **최소 브랜치로 승계된 것**: P1 blockers, 2-core, vacuum 하이브리드, sysop 수명 — 나머지는 기각(별도 PR 검토 대상).
- 감사 문서: `docs/report-pr7504-lifetime-audit-20260724.md`, `docs/report-pr7504-direct-ownership-matrix-20260724.md`(Codex), 구 최종보고 `docs/report-pr7504-redesign-phase4-final-20260724.md`는 rejected experiment의 이력 문서로 동결.

## 5. 사고·교훈 (재발 방지 반영분)
- diagdb 전체 역방향 덤프의 /tmp tmpfs 포화(5.24GB) → 캠페인 전체 로그 덤프 유틸 0회 규칙 + preflight/watchdog 하네스화.
- pgrep/pkill 패턴의 `\|` 리터럴 오판 2회(라이브 러너 오살 1회 포함) → `[/]` 패턴·PID exe 검증 규율.
- runtime-dev 볼륨 bestspace 헤더 이상(원인 미상, base도 동일 실패 — PR 무관) → 성능 측정은 tip 볼륨 공유로 전환, dev 볼륨은 조사 대상으로 격리.
- wrapper ready-check 플레이크, 모니터 self-match, optdebug checkdb 저속 등 하네스 이슈 전부 원인 분리 기록(제품 결함으로 미분류).
