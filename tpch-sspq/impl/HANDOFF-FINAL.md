# 최종 인수 문서 — 캠페인 `tpch-sspq-impl-r1-20260803`

작성 2026-08-05, head `7f027ea` (`origin/main` 도달성 검증 완료).
규범 `tpch-sspq/IMPL-SSOT.md` @ `eccdd1ae58cd733ed3121585146d68b9ae54a73f`,
blob `15b42ddca521444fa54b34b0fa8477ed2df643f6`, 1653행, AMEND-A..G.

이 문서는 **순서대로** 읽으면 된다. §1은 **네가 먼저 처리할 것**, §2는 그게 끝나면 다음 세션에
붙여 넣을 프롬프트, §3은 참고 자료다.

---

# §1. 네가 먼저 처리할 것 (Phase 2 개시 전 필수)

## 1-A. 반드시 필요 — 이것 없이는 Phase 2가 의미 없다

### ① §6-d-1 restart-variance 결합규칙 선택

**왜 막히는가**: Phase 2의 accept 판정(§7-a 조건 3)은 "개선폭 ≥ corrected MDE"다. corrected
MDE는 `inflation × paired_CV_fast`로 만들고, 그 `inflation`을 6개 보정점에서 어떻게 합칠지가
미결이다. 규칙이 없으면 A/B를 돌려도 이겼는지 졌는지 말할 근거가 없다.

**왜 내가 못 골랐는가**: 6개 측정점이 어느 규칙도 지지하지 않는다.
- 측정 인자: Q01 **15.3158** · Q02 1.4039 · Q03 1.4516 · Q04 1.4760 · Q05 2.2719 · Q06 **6.4235**
- 단일 pooled 불가 — 범위 비율 **10.909** > 선언 정지 비율 10
- 벽시계 의존 불가 — 전체 r=0.7150이 임계 0.70을 겨우 넘지만 **leave-one-out에서 Q01 제외 시
  r=0.3928, Q04 제외 시 0.6878**로 6개 중 2개 부분표본이 임계 미달. 상관이 개별 점에 얹혀 있다
- 모형 직접 반증 — Q03(4.539 s, 1.4516)과 Q06(3.846 s, 6.4235)은 벽시계 1.18배 차이인데 인자
  4.43배 차이
- **불안정의 기전까지 규명됨** — 비율의 분모인 fast 레짐 paired CV가 극단 인자 질의에서 분해능
  바닥이다(Q01 0.000972, Q06 0.001123, 각각 **3 pair** 추정). ~0.1% 산포를 3 pair로 추정한 값을
  분모로 쓰는 비율은 안정량이 아니다
- 추가 진단 — 재기동 페널티가 **가법적**일 가능성이 더 크다(가법 모형 상대 SD 0.8930 vs 곱셈
  1.1724). 그러면 max 인자 fail-safe가 정작 보정이 가장 덜 필요한 질의를 가장 심하게 과보정한다

**선택지**

| 선택 | 내용 | 결과 |
|---|---|---|
| (a) pooled 기하평균 | 2.9598 일괄 | 아래 5행 중 3행이 resolvable |
| (b) 벽시계 의존 | 회귀식 적용 | 5행 전부 resolvable |
| (c) max 인자 | 15.3158 일괄 (과보정, 안전측) | 5행 전부 unprovable |
| (d) 보정 확장 | fast·restart **두 레짐을 대칭 확장**하고 pairing 규칙을 다시 핀(§6-d-1 step 2 개정 필요) | 미정 — 측정으로 결정. **규범 개정 선행, Phase 2 지연** |

**내 권고: Phase 2를 시작하려면 (c) max 15.3158.** 안전측이라 false accept를 만들지 않고
즉시 진행된다. 대신 진짜 개선을 놓칠 수 있고, (c)에서 unprovable로 뜨는 5행 중 하나가 실제로
중요해지면 그때 (d)를 별도 작업으로 승인하면 된다.

(처음에는 (d)를 권했는데 **철회한다.** (d)는 "블록만 더 모으면 되는 일"이 아니다 — §6-d-1
step 2가 두 레짐의 pairing 규칙을 동일하게 핀하도록 못박고 있어서, 분모를 줄이려면 두 레짐을
대칭 확장하고 pairing을 다시 핀하는 **규범 개정**이 선행한다. 상세는 아래 "보정 추가 수집" 절.
경계 코호트가 내 최초 권고의 절차가 실행조차 되지 않는다는 것과, 고친 뒤에도 `paired_cv`가
재추정되지 않는다는 것을 차례로 잡아냈다.)

**이 결정이 실제로 가르는 것은 5행뿐이다.** 나머지 7행은 세 규칙에서 결과가 같다.

| 후보 | 질의 | (a) pooled | (b) 벽시계 | (c) max |
|---|---|---|---|---|
| IMP-012 | Q08 | unprovable | **resolvable** | unprovable |
| IMP-013 | Q08 | unprovable | **resolvable** | unprovable |
| IMP-015 | Q10 | resolvable | resolvable | **unprovable** |
| IMP-030 | Q22 | resolvable | resolvable | **unprovable** |
| IMP-031 | Q22 | resolvable | resolvable | **unprovable** |

### ② Phase 1 랭킹·후보 큐 승인

§11-b phase gate. 승인 없이 Phase 2 개시 금지.

**상위 5**: IMP-015 76.5 · IMP-009 72.9 · IMP-018 72.1 · IMP-014 72.0 · IMP-027 70.5

**큐 (22개)**: IMP-015 → IMP-005 → IMP-009 → IMP-018 → IMP-014 → IMP-027 → IMP-003 →
IMP-029 → IMP-019 → IMP-023 → IMP-030 → IMP-013 → IMP-012 → IMP-031 → IMP-022 → IMP-016 →
IMP-004 → IMP-021 → IMP-010 → IMP-008 → IMP-024 → IMP-006

**승인 전에 알아야 할 것**:
- `RANKING_UNSTABLE=True`. 증거가중 ±0.15 섭동에서 **IMP-003 ↔ IMP-027**이 상위 5를 드나들고
  IMP-014 ↔ IMP-027 순서가 바뀐다. 그 구간의 큐 순서는 증거로 지지되지 않으니, 순서에 의존하는
  결정을 하지 마라
- IMP-027은 기대절감 43.60 s로 최대인데 feasibility 41.0이 총점을 누른다. "가장 큰 효과"를
  원하면 IMP-027, "가장 안전한 진행"을 원하면 순서대로
- **IMP-015는 이미 구현·측정되어 `accepted (provisional)`이다.** 재구현 대상이 아니라, 이 세션의
  Q15 진단이 적용 범위를 좁혔으므로(리더가 해시 패스를 수행하는 group-by에 한정) 재검토 대상

## 1-B. Phase 2를 막지는 않지만 빠를수록 좋은 것

| # | 항목 | 없으면 |
|---|---|---|
| ③ | **IMP-001 분모** — 프로토타입 ~13%가 wall인지 CPU인지 | IMP-001이 계속 `BENEFIT_PENDING_DENOMINATOR`로 랭킹 제외 |
| ④ | **상류 티켓 per-candidate 매핑** — CBRD-27127/27036/27037/27094/27113, PR #7453 | IMP-003·022·019·011·014가 6건 전부에 대해 §5-e 게이트를 통과해야 한다 |
| ⑤ | **NEW-CAND-A ID 할당 여부** — Q15 진단이 찾은 신규 후보. 성능 arm과 측정정확성 arm을 하나로 볼지 둘로 나눌지도 | 후보화 불가(§1-b, `next_id`는 `IMP-032`로 소진) |
| ⑥ | **IMP-019 / IMP-020 Notion 정체** — 두 페이지의 `IMP ID` 번호와 제목 접두가 엇갈림 | 미러 2건이 §10-f 백필 상태로 남음 |
| ⑦ | **§8-e gate scratch 경로 예외 명문화** | 이탈 기록만 남고 규범 미반영 |
| ⑧ | **`external_tracking` 종결(OQ-F4)** — PR #7533 병합 여부, CBRD-26788 해결 방식 | 캠페인 종결 불가 |

---

# §2. 다음 세션에 붙여 넣을 프롬프트

아래 코드블록 전체를 그대로 넣으면 된다. **§1-A ①②를 결정한 내용으로 `[[ ]]` 두 곳만 채워라.**

```text
캠페인 tpch-sspq-impl-r1-20260803을 인수해 Phase 2를 수행한다.

## 사용자 결정 (이미 내려졌다)

- §6-d-1 결합규칙: [[ (a) pooled 기하평균 2.9598 / (b) 벽시계 의존 / (c) max 15.3158 /
  (d) 보정 블록 추가 수집 후 재판단 — 하나를 적어라 ]]
- Phase 1 랭킹·후보 큐: [[ 승인한다 / 다음 수정 후 승인한다: … ]]

(d)를 골랐다면 Phase 2를 시작하지 말고 보정 블록 추가 수집부터 하라 — 아래 "보정 추가 수집"
절을 따르고, 규칙이 정해지면 그때 Phase 2로 넘어간다.

## 규범과 인수 문서

규범: ~/dev/workspace/tpch-sspq/IMPL-SSOT.md — commit
eccdd1ae58cd733ed3121585146d68b9ae54a73f, blob 15b42ddca521444fa54b34b0fa8477ed2df643f6,
1653행, AMEND-A..G. 착수 전 §1-d대로 git fetch origin main 후 핀을 검증하고 끝까지 읽어라.
이 프롬프트와 SSOT가 충돌하면 SSOT가 이긴다.

인수: tpch-sspq/impl/HANDOFF-FINAL.md 를 정독하라. 환경 지식은
tpch-sspq/impl/CAMPAIGN-PAUSE.md §5에 있다 — 재발견하지 말고 그대로 적용하라.
산출물: priority-ranking.md/.json, fresh-baseline.md/.json,
restart-variance-calibration.json, benefit-inputs.json, diagnosis/Q15-parallel-non-arming.md.

**중요**: 문서 서술을 근거로 쓰지 말고 산출물 JSON을 직접 읽어라. 지난 세션에서 요약 문서의
손 전사 오류가 네 세대 연속 발견됐다. 문서는 지도이고 산출물이 영토다.

## 절대 경계

- 새 IMP ID 할당 금지(§1-b, next_id=IMP-032 소진). 후보화가 필요하면 "ID 미할당 신규 후보"로
  올려 사용자 결정 항목에 넣어라.
- 스크래치는 /data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/ 하위만. /tmp·$TMPDIR 절대 금지.
- 타 사용자 상주 프로세스(pxidx cub_server, tmux 1gjc/claude, codex 스택, gjc bun 데몬,
  VTune, tradingcodex) 불가침(§3-b). 캠페인 소유 서버만 정지 가능.
- cubrid 명령 파이프 금지 — 무한 대기한다. timeout과 </dev/null로 파일 리다이렉트.
- 장시간 작업은 tmux 자식 드라이버로. nohup·setsid·disown 금지(§8-b).
- 대용량 출력을 그대로 캡처하지 마라. 파일로 리다이렉트하고 grep/head/wc로 읽어라. 이
  캠페인에서 실제로 세션이 메모리 폭주로 죽었다.
- git rebase/reset --hard/clean -fd/force push/history rewrite 금지. git add는 의도한 경로만
  (never -A). 작업 트리에 다른 세션의 미커밋 IMP-032 파일 4개가 있을 수 있다 — 건드리거나
  되돌리거나 커밋하지 마라.
- 내구성 = origin/main 도달 가능(§1-e): add → commit → push → merge-base --is-ancestor.
- 하니스 생성기는 **제자리에 쓴다**. calibrate_restart_variance.py는 argv 없이 부르면 기본
  출력 경로가 실제 저장소다. 검증용으로 돌릴 때는 입력을 scratch로 복사하고 출력 디렉터리를
  명시적으로 넘겨라.

## Phase 2 절차 (후보 1개당)

1. GJC 세션 1개 = IMP 1개(§8-b).
2. worktrees/IMP-NNN을 frozen base SHA 607f1ee9fb2394de129e083602c84a6525fc685c 에서 생성,
   브랜치 impl/tpch-sspq-impl-r1-20260803/IMP-NNN-<slug>. 한 브랜치 = 한 IMP = 한 가설,
   패치 스태킹 금지(§5-b).
3. implementation-plan.md를 **첫 소스 수정 전에** 후보 브랜치에 커밋(§5-c 10항목: 반증 가능한
   가설 / 변경할 CUBRID file:line / PostgreSQL 참조 file:line / 예상 파일과 LOC 밴드 /
   움직여야 하는 지표 signature와 방향 / 정확성 위험과 시험 방법 / 표적 질의 / 음성 대조 질의 /
   중복·의존 관계 / 롤백 방법).
4. §5-e 상류 스코프 게이트: IMP-003·022·019·011·014는 상류 티켓/PR 대조 결과를 계획서에 기록.
   **상류가 이미 커버하면 stop-and-report** — 병행 진행이나 범위 축소 사유가 아니다.
5. 빌드는 §6-a-1 핀 레시피 그대로. INSTALL_PREFIX 필수(~/CUBRID 재지정 금지),
   taskset -c 24-31 just build release, CMakeUserPresets.json 부재 어서션, 사전 검증 6항목.
   런타임 conf는 §6-a-2 핀(sha256 ad19f5ac…)을 base와 patch에 동일하게.
6. 정확성 게이트 5종 전부(§6-b): 후보 특화 단위·회귀 / 표적 질의 / q_relations 전 질의 /
   Q01~Q22 결과 스모크 / 동시성·메모리 후보는 별도 스트레스·진단 빌드. **어떤 차이도 실패**이며
   즉시 정지·에스컬레이션.
7. A/B는 §6-c — Phase 1A와 달리 **블록마다 재기동**. B → P → P → B, 블록마다 affinity·NUMA·
   all-TID·ownership 게이트와 WARM 증명, 1 uncounted warmup + 3 measured, 최소 3 사이클
   = 변종별 6 블록 median.
8. 통계는 §6-d: paired block-median P/B 비 + paired bootstrap 95% CI, accept는 위에서 결정된
   결합규칙의 corrected MDE 기준. 12 pair까지 CI가 1.0을 포함하면 inconclusive이고 사용자
   지시 없이 pair 추가 금지(§7-b).
9. 판정은 §7-a(accept 5조건 전부) / §7-c(reject) / §7-e. 예상 밖 결과를 은폐하지 마라 —
   반대 방향이거나 2배 이상 이탈하면 근본 원인을 재조사하고 원 증거 귀속이 틀렸을 가능성까지
   보고하라.
10. 정지 조건(§5-d, §11-a): high-LOC 추정 150% 초과 / 예상 밖 서브시스템·XASL 직렬화·영속
    형식·락 프로토콜 접촉 / 정확성 불일치 / 통제 불가한 A/B 플랜 변경 / 비표적 질의 3% 초과
    회귀 / 반대 방향 효과.

## 큐와 후보별 함정

큐(22개): IMP-015 → IMP-005 → IMP-009 → IMP-018 → IMP-014 → IMP-027 → IMP-003 → IMP-029 →
IMP-019 → IMP-023 → IMP-030 → IMP-013 → IMP-012 → IMP-031 → IMP-022 → IMP-016 → IMP-004 →
IMP-021 → IMP-010 → IMP-008 → IMP-024 → IMP-006

- IMP-017은 큐에 **없다** — diagnostic 레인은 §4-a에 따라 큐 위치가 없다. IMP-016의 메모리
  arm을 시험 가능하게 만드는 선행 조건이지만 큐 항목으로 착수할 대상이 아니다.
- IMP-015는 이미 accepted (provisional). 재구현이 아니라 적용 범위 축소 반영 후 재검토.
- IMP-005(enabler)는 IMP-009·IMP-012의 측정 선행 조건이고 같은 176행 파일을 공유한다 —
  순서 필수.
- IMP-006·IMP-023·IMP-024는 **XASL 직렬화**를 건드린다 — §5-d 독립 hard stop.
- IMP-010·IMP-013·IMP-018은 **write path** — 첫 코드 한 줄 전에 stop-and-report(§11-a).
- IMP-021 ⊃ IMP-015, IMP-023 — IMP-021이 먼저 들어가면 앞의 둘이 가속하려던 워크로드가
  사라진다. 순서가 결과를 좌우한다.
- IMP-003 / IMP-022는 같은 함수 영역을 수정해 한 브랜치 규칙과 충돌한다.
- IMP-030의 수락 기준은 "결과 불변"일 수 없다 — 교체 구현이 현행 문자열 왕복보다 더 정확하다.
- Q11 베이스라인에는 caveat가 있다: 블록 median이 교환가능 표본이 아니라 추세(-16.10% 단조
  감소)이므로 paired CV가 추세를 재고 있다. Q11에 A/B를 하려면 노이즈 하한을 Phase 2의
  재기동 레짐에서 재도출하라.
- RANKING_UNSTABLE 구간(IMP-003 ↔ IMP-027, IMP-014 ↔ IMP-027)의 순서는 증거로 지지되지
  않는다.

## 보정 추가 수집 (사용자가 (d)를 고른 경우에만)

**먼저 읽어라 — (d)는 내가 처음 적은 것보다 비싸다.** 터미널 critic 4차·경계 코호트
generation 22가 두 단계에 걸쳐 이걸 잡았고, 정정된 사실은 다음이다.

1차 오류(고쳐짐): "`TPCH_SSPQ_BLOCKS`를 올려 드라이버를 돌려라"는 **아무 일도 하지 않았다** —
재개 가드가 `raw/<QNN>/QUERY-COMPLETE.json`이 있는 질의를 무조건 skip하고 Q01~Q06 마커가
전부 존재한다. 드라이버에 append 전용 모드를 넣어 고쳤다:

```bash
# BLOCK_START>1이면 재개 가드가 열리고 블록 번호가 거기서 시작한다.
# 대상 범위에 이미 블록이 있으면 조용히 넘어가지 않고 exit 3으로 거부한다.
TPCH_SSPQ_BLOCK_START=7 TPCH_SSPQ_BLOCKS=6 ./phase1a_fast_driver.sh Q01 Q02 Q03 Q04 Q05 Q06
```

**2차 오류(더 중요, 설계 제약)**: 블록을 추가해도 **`paired_cv`는 재추정되지 않는다.**
`aggregate_baseline.py`의 `ADJACENT = [(0,1),(2,3),(4,5)]` / `SPACED = [(0,3),(1,4),(2,5)]`는
6블록에 대해 **고정**되어 있고, 12블록을 넣어도 인덱스 0~5만 본다. 극단값을 넣어 직접 확인했다 —
6블록과 12블록의 `paired_cv`가 **비트 동일**하다.

그리고 이건 버그가 아니라 **규범 제약**이다. §6-d-1 step 2는 두 레짐의 paired CV를
"identical estimator와 identical pairing rule"로 계산해 "comparable by construction"이어야
한다고 못박는다. inflation은 두 값의 비율이므로, 한쪽 pairing만 넓히면 서로 다른 규칙으로
계산된 값을 나누게 되고 그게 바로 그 조항이 금지하는 것이다.

**따라서 (d)의 실제 비용**: 3-pair 분모 불확실성을 진짜로 줄이려면 **fast와 restart 두 레짐을
대칭으로 확장**하고 **새 pairing 규칙을 하나로 다시 핀**해야 한다. 즉 규범 개정(§6-d-1 step 2의
pairing 고정을 갱신)이 필요하고, 그것 자체가 §11-a 사용자 결정 사항이다. "블록만 더 모으면 되는
일"이 아니다.

그래서 선택은 이렇게 다시 읽어야 한다.

- (a) pooled 2.9598 · (b) 벽시계 의존 · (c) max 15.3158 — **즉시 진행 가능.** 6개 측정점이
  지지하지 않는 가정을 하나 얹는 대가로 Phase 2를 지금 시작한다. (c)는 false accept를 만들지
  않는 안전측이고, 대신 진짜 개선을 놓친다.
- (d) 보정 확장 — **규범 개정 + 두 레짐 재측정**이 선행한다. 통계적으로 가장 정직하지만 가장
  비싸고, Phase 2가 그만큼 늦어진다.

내 권고는 이제 이렇다: **Phase 2를 시작하려면 (c) max를 골라라.** 안전측이고 즉시 진행되며,
(c)에서 unprovable로 뜨는 5행 중 하나가 실제로 중요해지면 그때 (d)를 별도 작업으로 승인하면
된다. (d)를 먼저 하는 것은 그 5행의 판정이 지금 당장 중요할 때만 값어치가 있다.

확장이 승인되면 드라이버의 append 모드는 이미 준비돼 있고 안전하다 — 기존 증거를 덮어쓰지
않고, 충돌 시 `exit 3`으로 거부한다. `aggregate_baseline`도 추가 블록을 기록(개수·median·산포)
하지만 `paired_cv`는 핀된 pairing을 유지하며, 그 사실을 산출물에
`paired_cv_ignores_blocks_beyond_pinned_pairing: true`로 명시한다.

## 인수 시점의 기록 (live 상태는 직접 확인하라)

- **게이트 상태는 이 문서에 적지 않는다.** 워크플로 상태는 계속 움직이므로 여기 박아 두면
  낡는다. 현재 상태는 `gjc ultragoal status`와
  `.gjc/_session-*/ultragoal/ledger.jsonl`의 `critic_verdict` 이벤트로 직접 확인하라.
  generation 19는 미해결 채무가 아니라 레인 인프라 사건이며 generation 21이 그 범위를
  대체해 세 레인 clean으로 닫았다.
- 지난 세션이 잡은 가장 무거운 결함: aggregate_baseline._load_attempts()가 폐기된
  pre-AMEND-G 런의 로그를 읽어 baseline이 다른 런의 시도 무효화를 싣고 있었다(§3-a 위반).
  생산자를 핀된 fast 로그로 고치고 fail-closed 가드를 넣었다. 재생성 후 median·CV·MDE·인자·
  점수·순위·큐·민감도는 전부 불변이고 priority-ranking.json 수치 leaf 843개 중 변경 0건,
  fresh-baseline.json은 7,188개 중 13개(전부 시도 provenance 필드)만 변경됐다.
- harness/에 상주 단위 시험이 없다. Phase 2 전에 최소한 score_with()의 모집단·정렬 불변식과
  state_labels의 양방향 속성은 상주 시험으로 고정할 가치가 있다.

## 보고 규율

§8-c 상태 블록(TPCH_SSPQ_IMPL_STATUS)을 주기 방출하고, 정지 조건에 걸리면 즉시 상태 블록을
남기고 대기하라. 질문으로 멈추기보다 범위 안에서 자율 진행하되 §11-a 에스컬레이션 항목은
반드시 사용자 결정으로 올려라.
```

---

# §3. 참고

## Phase 2 이후 (§11-b 종결)

승인 큐 전원이 `accepted`/`rejected`/`inconclusive` 판정과 결정 기준을 갖고,
`implementation-results.json`에 브랜치 목록이 공표되고, 결과별 Git·raw·Notion 정합성이
검증된 뒤, **사용자 승인 후** frozen base SHA에서 누적 브랜치를 만들어 Q01~Q22 정확성과
누적 A/B를 돌린다. 최종 report·raw manifest 커밋·푸시·도달성 검증, 캠페인 세션·프로세스
부재 검증. **상류 병합은 또 별도 승인 대기** — 누적 브랜치 생성이 병합 허가가 아니다.

## 남긴 도구

| 파일 | 용도 |
|---|---|
| `harness/phase1a_fast_driver.sh` | AMEND-G fast 스윕 드라이버. 질의 단위 재개, Q15 세션 분기 |
| `harness/aggregate_baseline.py` | 블록 → 베이스라인. paired CV 추정량 단일 출처. 시도 provenance에 fail-closed 핀 검사 |
| `harness/calibrate_restart_variance.py` | §6-d-1 도출. 가드 G1~G4, 결합규칙 판단, 가법/곱셈 진단, stop-and-report |
| `harness/score_ranking.py` | §2 산술 전담. `score_with()`가 본 채점과 민감도의 유일한 구현이고, 민감도 base가 published 순서를 재현하지 않으면 실행을 거부 |
| `harness/render_baseline_md.py`, `render_ranking_md.py` | 보고서 렌더. §2를 핀 파일에서 렌더 시점에 바이트 단위 추출 |
| `harness/state_labels.py` | 상태 오기 방지 가드. 생성기가 자기 산출물을 상태별 금지 문구와 대조해 모순 출력을 거부. 쓰기 경로 6개 전부 |
| `impl/diagnosis/q15_diag_probe.sh` | Q15 진단 4 leg 힌트 대조쌍 재현 |

`state_labels.py`와 `aggregate_baseline`의 핀 검사를 우회하지 마라. 둘 다 실제로 발생한
결함에서 나왔다.

## Phase 1 결과 요약

- Phase 1A: Q01~Q22 전수, **131 블록 accepted / 1 invalid**(Q09 block 3), median wall 합계
  **262.5440 s**. 전 구간 단일 인스턴스, off_sut TID 0건.
- 시도 반려 11건, 전부 `INVALID_BACKGROUND_LOAD`: Q07 2 · Q08 1 · Q09 7 · Q13 1.
- Q15 진단: 미발동 게이트는 `external_sort.c:5232`, 근본 원인은 병렬 스캔 gather 경로에서
  리더가 튜플을 받지 않아 `agg_hash_context->state`가 `HS_ACCEPT_ALL`에 머무는 것이고,
  트레이스의 `hash: partial`은 `px_scan_result_handler.cpp:635`가 강제 대입한 라벨이다.
  게이트가 읽는 필드와 트레이스가 찍는 필드가 다르다.
- Notion 미러: 후보 31개 중 29개 동기화, IMP-019/020은 §10-f 백필.
