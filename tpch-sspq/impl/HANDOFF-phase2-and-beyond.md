# Handoff — 캠페인 `tpch-sspq-impl-r1-20260803`, Phase 1 완료 이후

작성 2026-08-05. 이 문서는 **다음 세션에 그대로 붙여 넣을 수 있는 지시문**이다. §2는 프롬프트
본문이고, §1은 그 프롬프트가 전제하는 사실 요약이다.

**가장 중요한 한 줄**: Phase 1은 산출이 끝났고 **Phase 2는 사용자 승인 전 개시 금지**다. 승인
없이 엔진 코드를 한 줄도 쓰지 마라.

---

## 1. 인수 시점의 사실

| 항목 | 값 |
|---|---|
| 규범 | `tpch-sspq/IMPL-SSOT.md` @ `eccdd1ae58cd733ed3121585146d68b9ae54a73f`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6`, 1653행, AMEND-A..G |
| 최신 커밋 | `46be92f` (`origin/main` 도달성 검증 완료) |
| CUBRID base SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (캠페인 전체 고정) |
| Phase 1A | 완료 — Q01~Q22, 131 블록 accepted / 1 invalid, median wall 합계 262.5440 s |
| Phase 1B | 랭킹·큐 산출 완료, `RANKING_UNSTABLE` 표시 |
| §6-d-1 결합규칙 | **STOP-AND-REPORT, 사용자 결정 대기** (`USER_DECISION_REQUIRED`) |
| Phase 2 | **미개시.** 엔진 소스 변경 0건, 새 IMP ID 0건 (`next_id`는 `IMP-032`로 소진) |
| Notion | 후보 31개 중 29개 동기화, IMP-019/020은 §10-f 백필 |

### 읽어야 할 산출물

- `tpch-sspq/impl/priority-ranking.md` / `.json` — 랭킹, 큐, §2-e 12열, 민감도, 보류 판정
- `tpch-sspq/impl/fresh-baseline.md` / `.json` — 베이스라인, 질의별 CV·MDE, divergence 비교
- `tpch-sspq/impl/restart-variance-calibration.json` — §6-d-1 도출과 escalation 근거
- `tpch-sspq/impl/benefit-inputs.json` — 후보별·질의별 판정(효과분율·증거등급·원자료 인용)
- `tpch-sspq/impl/diagnosis/Q15-parallel-non-arming.md` — 작업 2 진단
- `tpch-sspq/impl/CAMPAIGN-PAUSE.md` §5 — 환경 지식(재발견 금지)
- 원자료: `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/{raw,raw-restart-calibration,work}/`

### 승인 대기 8건 (§7 of the Notion record와 동일)

1. **§6-d-1 결합규칙 선택** — pooled(기하평균 2.9598) / 벽시계 의존 / max(15.3158) / 보정 블록
   추가 수집. 이 결정이 IMP-012·IMP-013(Q08), IMP-015(Q10), IMP-030·IMP-031(Q22) 5행의
   `UNPROVABLE_ON_THIS_HOST` 판정을 가른다. 나머지 7행은 세 규칙 전부 동일하다.
2. **Phase 1 랭킹·후보 큐 승인** — 이것 없이 Phase 2 개시 금지.
3. **NEW-CAND-A ID 할당 여부** — 작업 2의 신규 후보. 성능 arm과 측정정확성 arm을 하나로 볼지
   둘로 나눌지도 결정 필요.
4. **IMP-019 / IMP-020 Notion 정체** — `IMP ID` 번호와 제목 접두가 엇갈려 있다.
5. **§8-e gate scratch 경로 예외 명문화 여부**.
6. **IMP-001 분모** — 프로토타입 ~13%가 wall인지 CPU인지.
7. **상류 티켓 per-candidate 매핑** — 현재 set-to-set이라 IMP-003/022/019/011/014가 6건 전부에
   게이트된다.
8. **`external_tracking` 종결(OQ-F4)** — PR #7533 병합 여부, CBRD-26788 해결 방식.

---

## 2. 다음 세션용 프롬프트 (아래 블록을 그대로 사용)

```text
캠페인 tpch-sspq-impl-r1-20260803을 인수한다. Phase 1은 산출이 끝났고 너의 시작점은
사용자 승인 여부 확인이다.

규범: ~/dev/workspace/tpch-sspq/IMPL-SSOT.md — commit eccdd1ae58cd733ed3121585146d68b9ae54a73f,
blob 15b42ddca521444fa54b34b0fa8477ed2df643f6, 1653행, AMEND-A..G. 착수 전 §1-d대로
git fetch origin main 후 핀을 검증하고 이 파일을 끝까지 읽어라. 이 프롬프트와 SSOT가
충돌하면 SSOT가 이긴다.

인수 문서: ~/dev/workspace/tpch-sspq/impl/HANDOFF-phase2-and-beyond.md 를 먼저 정독하라.
환경 지식은 tpch-sspq/impl/CAMPAIGN-PAUSE.md §5에 있다 — 재발견하지 말고 그대로 적용하라.

## 절대 경계

- Phase 2(엔진 코드 작성)는 **사용자가 Phase 1 랭킹과 후보 큐를 명시적으로 승인한 뒤에만**
  개시한다. 승인 문구가 대화에 없으면 개시하지 마라. §11-b/Phase gate.
- §6-d-1 결합규칙이 아직 USER_DECISION_REQUIRED다. 인자를 **네가 고르지 마라**. 결정 전에는
  §7-a criterion 3(점 개선 ≥ MDE)을 판정할 수 없으므로 A/B accept 판정도 확정할 수 없다.
  corrected MDE에 의존하는 어떤 판정도 단정하지 말고 보류 상태를 유지하라.
- 새 IMP ID 할당 금지(§1-b, next_id=IMP-032 소진). 후보화가 필요하면 "ID 미할당 신규 후보"로
  올려 사용자 결정 항목에 넣어라.
- 스크래치는 /data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/ 하위만. /tmp·$TMPDIR 절대 금지.
- 타 사용자 상주 프로세스(pxidx cub_server, tmux 1gjc/claude, codex 스택, gjc bun 데몬, VTune,
  tradingcodex) 불가침(§3-b). 캠페인 소유 서버만 정지 가능.
- cubrid 명령 파이프 금지 — 무한 대기한다. timeout과 </dev/null로 파일 리다이렉트하라.
- 장시간 작업은 tmux 자식 드라이버로. nohup·setsid·disown 금지(§8-b).
- 대용량 출력을 그대로 캡처하지 마라. 파일로 리다이렉트하고 grep/head/wc로 필요한 부분만 읽어라.
  이 캠페인에서 실제로 세션이 메모리 폭주로 강제 종료된 적이 있다.
- git rebase/reset --hard/clean -fd/force push/history rewrite 금지. git add는 의도한 경로만
  (never -A). 작업 트리에 다른 세션의 미커밋 IMP-032 파일 4개가 있을 수 있다 —
  건드리거나 되돌리거나 커밋하지 마라.
- 내구성 = origin/main 도달 가능(§1-e): add → commit → push → merge-base --is-ancestor 확인.

## 승인이 아직 없다면

Phase 2를 시작하지 말고, 대신 다음 중 사용자가 지시한 것만 수행하라.
(a) 승인 대기 8건을 정리해 다시 제시하고 대기,
(b) §6-d-1 보정 블록 추가 수집(결합규칙을 모형 선택이 아니라 측정으로 결정하는 길). 이 경우
    Q01~Q06을 fast 레짐에서 블록 수를 늘려 재측정해 fast CV의 3-pair 불확실성을 줄인다.
    드라이버는 tpch-sspq/impl/harness/phase1a_fast_driver.sh, TPCH_SSPQ_BLOCKS로 블록 수를
    올릴 수 있다. 핀 파라미터(WARM 게이트, 6.0 게이트, 1 warmup + 3 measured)는 바꾸지 마라.
(c) 랭킹 재검토 — 사용자가 IMP-001 분모나 상류 매핑을 제공하면 benefit-inputs.json의 해당
    항만 갱신하고 harness/score_ranking.py와 두 렌더러를 재실행하라. 판정은
    benefit-inputs.json에만, 산술은 score_ranking.py에만 둔다는 분리를 깨지 마라.

## 승인이 있다면 — Phase 2 절차 (후보 1개당)

1. GJC 세션 1개 = IMP 1개(§8-b). Phase 1A의 단일 드라이버 예외는 Phase 1A 한정이다.
2. worktrees/IMP-NNN을 frozen base SHA에서 생성, 브랜치
   impl/tpch-sspq-impl-r1-20260803/IMP-NNN-<slug>. 한 브랜치 = 한 IMP = 한 가설, 스태킹 금지.
3. implementation-plan.md를 **첫 소스 수정 전에** 후보 브랜치에 커밋(§5-c 10항목).
4. §5-e 상류 스코프 게이트: IMP-003·022·019·011·014는 상류 티켓/PR 대조 결과를 계획서에
   기록. 상류가 이미 커버하면 **stop-and-report** — 병행 진행이나 범위 축소 금지.
5. 빌드는 §6-a-1 핀 레시피 그대로. INSTALL_PREFIX 필수(~/CUBRID 재지정 금지),
   taskset -c 24-31 just build release, CMakeUserPresets.json 부재 어서션, 사전 검증 6항목.
   런타임 conf는 §6-a-2 핀(sha256 ad19f5ac…)을 base와 patch에 동일하게.
6. 정확성 게이트 5종 전부(§6-b). 어떤 차이도 실패이며 즉시 정지·에스컬레이션.
7. A/B는 §6-c — Phase 1A와 달리 **블록마다 재기동**한다. B → P → P → B, 블록마다 affinity·
   NUMA·all-TID·ownership 게이트와 WARM 증명, 1 uncounted warmup + 3 measured, 최소 3 사이클.
8. 통계는 §6-d. paired block-median 비 + paired bootstrap 95% CI, accept는 **corrected MDE**
   기준. 12 pair까지 CI가 1.0을 포함하면 inconclusive이고 사용자 지시 없이 pair 추가 금지.
9. 판정은 §7-a/§7-c/§7-e. 예상 밖 결과를 은폐하지 마라 — 반대 방향이거나 2배 이상 이탈하면
   근본 원인을 재조사하고 원 증거 귀속이 틀렸을 가능성까지 보고하라.
10. 정지 조건(§5-d, §11-a): high-LOC 추정 150% 초과 / 예상 밖 서브시스템·XASL 직렬화·영속
    형식·락 프로토콜 접촉 / 정확성 불일치 / 통제 불가한 A/B 플랜 변경 / 비표적 질의 3% 초과
    회귀 / 반대 방향 효과.

## 큐와 후보별 주의 (전문은 priority-ranking.md)

큐(22개): IMP-015 → IMP-005 → IMP-009 → IMP-018 → IMP-014 → IMP-027 → IMP-003 → IMP-029 →
IMP-019 → IMP-023 → IMP-030 → IMP-013 → IMP-012 → IMP-031 → IMP-022 → IMP-016 → IMP-004 →
IMP-021 → IMP-010 → IMP-008 → IMP-024 → IMP-006.

IMP-017은 큐에 없다 — diagnostic 레인은 §4-a에 따라 큐 위치를 갖지 않는다. IMP-016의
메모리 arm을 시험 가능하게 만드는 선행 조건이지만 큐 항목으로 착수할 대상이 아니다.
enabler인 IMP-005만 IMP-009 바로 앞 위치를 상속해 큐에 들어간다.

- IMP-015는 이미 구현·측정되어 accepted (provisional)이다. 재구현 대상이 아니라, 작업 2가
  좁힌 적용 범위(리더가 해시 패스를 수행하는 group-by에 한정)를 반영해 재검토할 대상이다.
- IMP-005는 IMP-009·IMP-012의 측정 선행 조건이고 같은 176행 파일을 공유한다 — 순서 필수.
- IMP-006·IMP-023·IMP-024는 XASL 직렬화를 건드린다 — §5-d 독립 hard stop.
- IMP-010·IMP-013·IMP-018은 write path — 첫 코드 한 줄 전에 stop-and-report(§11-a).
- IMP-021 ⊃ IMP-015, IMP-023 — IMP-021이 먼저 들어가면 앞의 둘이 가속하려던 워크로드가
  사라진다. 순서가 결과를 좌우한다.
- IMP-003 / IMP-022는 같은 함수 영역을 수정해 한 브랜치 규칙과 충돌한다.
- IMP-030의 수락 기준은 "결과 불변"일 수 없다 — 교체 구현이 현행 문자열 왕복보다 더 정확하다.
- Q11 베이스라인에는 caveat가 있다: 블록 median이 교환가능 표본이 아니라 추세(-16.10% 단조
  감소)이므로 paired CV가 추세를 재고 있다. Q11에 A/B를 하려면 노이즈 하한을 Phase 2의
  재기동 레짐에서 재도출하라.
- RANKING_UNSTABLE 구간(IMP-003 ↔ IMP-027, IMP-014 ↔ IMP-027)의 순서는 증거로 지지되지
  않는다. 그 구간에서 순서에 의존하는 결정을 하지 마라.

## Phase 2 이후 (§11-b)

승인 큐 전원이 판정과 결정 기준을 갖고, implementation-results.json에 브랜치 목록이 공표되고,
결과별 Git·raw·Notion 정합성이 검증된 뒤, **사용자 승인 후** frozen base SHA에서 누적 브랜치를
만들고 Q01~Q22 정확성과 누적 A/B를 돌린다. 최종 report·raw manifest 커밋·푸시·도달성 검증,
캠페인 세션·프로세스 부재 검증. **상류 병합은 또 별도 승인 대기** — 누적 브랜치 생성이 병합
허가가 아니다.

## 보고 규율

§8-c 상태 블록(TPCH_SSPQ_IMPL_STATUS)을 주기 방출하고, 정지 조건에 걸리면 즉시 상태 블록을
남기고 대기하라. 질문으로 멈추기보다 handoff 범위 안에서 자율 진행하되, §11-a 에스컬레이션
항목은 반드시 사용자 결정으로 올려라.
```

---

## 3. 이 세션이 남긴 도구 (재사용 권장)

| 파일 | 용도 |
|---|---|
| `harness/phase1a_fast_driver.sh` | AMEND-G fast 스윕 드라이버. 질의 단위 재개(`QUERY-COMPLETE.json` 마커), Q15 세션 분기 포함 |
| `harness/aggregate_baseline.py` | 블록 → 베이스라인 축약. paired CV 추정량의 **단일 출처** |
| `harness/calibrate_restart_variance.py` | §6-d-1 도출. 가드 G1~G4, 결합규칙 판단, 가법/곱셈 진단, stop-and-report 경로 |
| `harness/score_ranking.py` | §2 산술 전담. `score_with()`가 본 채점과 민감도의 **유일한** 구현이고, 민감도 base가 published 순서를 재현하지 않으면 실행을 거부한다 |
| `harness/render_baseline_md.py`, `render_ranking_md.py` | 보고서 렌더. §2를 핀 파일에서 렌더 시점에 바이트 단위 추출 |
| `harness/state_labels.py` | **상태 오기 방지 가드.** 생성기가 자기 산출물을 상태별 금지 문구와 대조해 모순 출력을 거부한다. 쓰기 경로 6개 전부 적용 |
| `impl/diagnosis/q15_diag_probe.sh` | Q15 진단의 4 leg 힌트 대조쌍 재현 |

`state_labels.py`를 우회하지 마라. 그것이 존재하는 이유는 "상태에 의존하는 서술을 상태로
조건화하지 않는" 결함이 이 캠페인에서 아홉 번 반복됐고 매번 리뷰가 놓쳤기 때문이다. 통제를
리뷰에서 생성기로 옮긴 결과물이다.

## 4. 미해결 채무 (정직한 기록)

- **경계 완료 코호트 generation 12가 미완**이다. 세 레인이 인프라 사유로 3회 재시도 후 실패했고
  (레인 실패이며 결함 발견이 아니다), generation 11의 blocker 3건은 `46be92f`에서 수정했으나
  그 수정에 대한 코호트 심사와 터미널 critic 재심사가 남아 있다. 따라서 **G004는 아직
  `review_blocked`이고 ultragoal 실행은 완료로 표시되지 않았다.** 다음 세션이 Phase 2로 넘어가기
  전에 이 게이트를 닫는 것이 정직한 순서다. frozen `sourceHash`는
  `sha256:3f082b76043e71f7c13aed9e63918c79143c563fdf5e3ae4b6351627ce302a2f`(base `d5217c6`,
  head `46be92f`)이며 재계산으로 검증했다.
- 터미널 critic 누적 non-OKAY 판정 2회(ITERATE). 규범상 ceiling은 5이고 아직 여유가 있다.
- `harness/`에 단위 시험이 없다. 생성기의 계약은 코호트 QA 레인이 매 세대 재작성해 검증했으나
  저장소에 상주하는 시험은 없다. Phase 2로 가기 전에 최소한 `score_with()`의 모집단·정렬
  불변식과 `state_labels`의 양방향 속성은 상주 시험으로 고정할 가치가 있다.
