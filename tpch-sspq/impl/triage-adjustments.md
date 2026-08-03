# 트리아지 조정 사항 — Phase 1B benefit 입력 보정

- 캠페인: `tpch-sspq-impl-r1-20260803`
- 출처: Notion improvement-registry 근거를 바탕으로 사용자가 주도한 트리아지 논의
- 기계 판독용 정본: `tpch-sspq/impl/triage-adjustments.json` (이 문서는 그 해설이며, 충돌 시 JSON이 우선)
- 대응 IMPL-SSOT 개정: `AMEND-F` (section 2-b-1, 4-a, 5-e)

이 문서는 작업 기록이다. 왜 각 조정이 **랭킹을 바꾸는지**만 적는다.

---

## 1. Benefit 재산정 대상

### IMP-001 — `BENEFIT_PENDING_DENOMINATOR`

내부 프로토타입이 실제 효과를 **≈13%** 로 측정했다. 이는 **62.35%** profile band 전체가
제거 가능하다는 가정을 **반증**한다. 그러나 13%의 **분모가 확인되지 않았다**: wall-time
감소인지 CPU-time 감소인지 모른다.

이것이 랭킹에 결정적인 이유는 `expected_saved_seconds`가
`fresh_base_median_q`(= wall-clock 중앙값)에 효과 비율을 곱하기 때문이다. CPU 쪽 13%를
wall 중앙값에 곱하면 benefit이 과대평가되며, 이 후보의 대상 작업이 병렬화되는 성질이라
과대평가 배수가 클 수 있다.

따라서 IMP-001은 분모가 사용자에 의해 확정될 때까지 **숫자 benefit 점수도, 랭크 위치도
받지 않는다**. **탈락(reject)이 아니다** — 단 하나의 데이터에 막혀 있을 뿐이다.
(→ `open_questions` OQ-F1)

### IMP-002 — `BENEFIT_CONFOUNDED`

Q04의 **1.160 core-s** attribution이 **IMP-018 메커니즘과 교란(confound)** 되어 있다.
IMP-018과 IMP-010이 고쳐지기 전까지 이 benefit은 신뢰할 수 없다. 이번 캠페인 랭킹에서의
실효 evidence weight는 **0.00**이다.

주의: IMP-002는 `feasibility-assessment.json`에서 이미 `deferred_research` 레인이다
(CUBRID에 `BufferAccessStrategy` 등가물이 없기 때문). 이 두 사유는 **서로 독립**이며
**둘 다 기록·유지**된다. 레인 판단은 feasibility 판단이고, `BENEFIT_CONFOUNDED`는 근거
판단이다. 한쪽이 해소되어도 다른 쪽은 남는다.

### IMP-012 — discovery Priority와의 불일치 기록

절대 효과는 **0.138 s의 projection**이다. 이 절대 크기는 registry의 **P0** priority를
뒷받침하지 못한다.

다만 registry / Notion의 discovery `Priority` 필드는 **덮어쓰지 않는다**. discovery 쪽
Priority(발견이 얼마나 흥미로운가)와 캠페인 쪽 rank(구현이 wall time을 얼마나 벌어주는가)는
다른 질문이다. 불일치는 **캠페인 자체 필드에만** 기록한다. 랭킹은 IMPL-SSOT section 2-b에
따라 0.138 s projection에 **Projection evidence weight 0.50**을 적용해 계산한다.

### IMP-013 — benefit 산정 기준 교정

benefit은 **32.7% band 상한**이 아니라 **현실적 목표치 0.47 core-s**에서 계산해야 한다.
이는 section 2-b의 기존 규칙 두 개를 그대로 적용한 것이다: profile band 전체를 자동으로
제거 가능한 효과로 보지 않는다, 그리고 범위로 주어진 효과는 보수적 하한을 쓴다.
32.7% band는 **비용 관측치**이지 효과가 아니다.

---

## 2. 레인 / 상태 변경

| ID | 새 레인 | 사유 | 외부 참조 |
|---|---|---|---|
| IMP-028 | `external_tracking` | PR #7533에 의해 대체됨 | `#7533` |
| IMP-025 | `external_tracking` | PR #7533에 의해 대체됨 | `#7533` |
| IMP-007 | `external_tracking` (status `watch`) | CBRD-26788 상류 진행 중 | `CBRD-26788` |

세 후보 모두 이번 캠페인의 **자체 구현 대상에서 제외**된다. 다만 닫힌 것이 아니라
**해결까지 추적(tracking)** 해야 한다 — 그래서 새 레인이 필요했다.

IMP-025는 원래 `performance` 레인이었으므로 이 변경은 **랭킹 대상 집합 자체를 줄인다**.
이는 소유권 변경이지 benefit 판단이 아니다.

---

## 3. 상류 scope-check 게이트 (IMPL-SSOT section 5-e)

대상: **IMP-003, IMP-022, IMP-019, IMP-011, IMP-014**

구현 착수 전에 다음 상류 작업들과 scope를 대조해야 한다:
`CBRD-27127`, `CBRD-27036`, `CBRD-27037`, `CBRD-27094`, `CBRD-27113`, PR `#7453`.

**중요한 기록 방식**: 트리아지는 이 참조들을 **후보별 매핑이 아니라 집합(set)으로** 제시했다.
어느 티켓이 어느 후보에 걸리는지는 말하지 않았다. 따라서 여기서도 **set-to-set으로만**
기록하고, 각 게이트 후보는 **여섯 개 전부**와 대조한다. 없는 특정성을 지어내지 않기
위해서다. (→ OQ-F3)

상류가 이미 해당 scope를 덮고 있으면 그것은 **stop-and-report 조건**이며, 병행 진행의
근거가 아니다. 대조 결과는 그 후보의 `implementation-plan.md`에 기록한다.

---

## 4. 근거가 건전함이 확인된 후보 (긍정적 발견)

**IMP-027, IMP-011, IMP-014, IMP-015, IMP-018, IMP-010** 의 direct A/B 근거를 트리아지에서
검토했고 **결함이 없었다**.

이것은 결함 목록에 없다는 소극적 사실이 아니라 **적극적 발견**이다. 해당 후보들의 benefit
입력에 대한 신뢰도를 올리므로, 각 후보의 **ranking rationale에 드러나야 한다**.
evidence weight 자체는 바뀌지 않는다(direct A/B는 이미 1.00) — 그 1.00이 **근거 있는
1.00임이 확인**된 것이다.

---

## 5. 해소하지 않고 보존한 긴장

**IMP-011과 IMP-014는 3절(상류 scope 게이트)과 4절(근거 건전)에 동시에 등장한다.**
둘 다 동시에 성립한다. 근거가 건전하다는 것은 **비용이 실재한다**는 뜻이지,
**그 수정이 여전히 이번 캠페인의 몫**이라는 뜻이 아니다. 건전한 근거는 상류 scope
검사를 면제하지 않는다. 이 문장은 IMPL-SSOT section 5-e 마지막 항목에도 규범으로 박아
두었다.

그 밖에 보존한 불일치는 `triage-adjustments.json`의 `preserved_tensions` 및
`contradictions_with_pinned_inputs`를 참조한다. 어느 것도 이 작업에서 일방적으로
해소하지 않았다.
