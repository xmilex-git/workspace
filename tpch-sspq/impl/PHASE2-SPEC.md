# Phase 2 확정 스펙 — 캠페인 tpch-sspq-impl-r1-20260803

작성 2026-08-05. 규범: IMPL-SSOT.md @ eccdd1ae58cd733ed3121585146d68b9ae54a73f
(blob 15b42ddca521444fa54b34b0fa8477ed2df643f6, 1653행, AMEND-A..G — origin/main 도달성
검증 완료). 이 문서와 SSOT가 충돌하면 SSOT가 이긴다.

**개시 게이트: Phase 2는 사용자가 명시적으로 개시를 지시하기 전에는 시작하지 않는다.**

## 1. 사용자 결정 기록

### ② Phase 1 랭킹·후보 큐 — 승인됨 (2026-08-05, 수정 1건 포함)

- 사용자 결정: "순서는 인정. IMP-015는 이미 볼대로 다 봤으니 이후로 넘어간다."
- 효력: 큐 순서 승인. **IMP-015 재검토 항목은 종결 처리**(기존 accepted (provisional)
  판정과 이 캠페인의 Q15 진단에 따른 적용 범위 축소 기록을 그대로 유지). Phase 2 착수
  지점은 **IMP-005**.
- 확정 큐 (21개): IMP-005 → IMP-009 → IMP-018 → IMP-014 → IMP-027 → IMP-003 →
  IMP-029 → IMP-019 → IMP-023 → IMP-030 → IMP-013 → IMP-012 → IMP-031 → IMP-022 →
  IMP-016 → IMP-004 → IMP-021 → IMP-010 → IMP-008 → IMP-024 → IMP-006
- 조건: RANKING_UNSTABLE 구간(IMP-003 ↔ IMP-027, IMP-014 ↔ IMP-027)의 순서는 증거로
  지지되지 않으므로 순서 의존 결정 금지.

### 추가 사용자 결정 (2026-08-05, 2차): 타인 진행 중 IMP 재검토 금지

- "이미 다른 사람들이 다루고 있는 IMP들은 우리가 재검토하지는 않기로 하자."
- 적용: IMP-027(CBRD-27171, 동일 결함), IMP-014·IMP-003·IMP-019·IMP-022(§5-e
  upstream set: CBRD-27127/27036/27037/27094/27113 + PR #7453). IMP-011은 큐 외.
- 효력: 이 5개 후보는 구현·측정 없이 external_tracking 처분(§4-a, 외부 레퍼런스 필수
  기재)으로 종결한다. 착수 시점에 상류 레퍼런스의 그 시점 상태를 확인·기록만 한다.
- 실행 큐 잔여(구현 대상 16개): IMP-005 → IMP-009 → IMP-018 → IMP-029 → IMP-023 →
  IMP-030 → IMP-013 → IMP-012 → IMP-031 → IMP-016 → IMP-004 → IMP-021 → IMP-010 →
  IMP-008 → IMP-024 → IMP-006

### ① §6-d-1 restart-variance 결합규칙 — **확정: (c) max 15.3158 일괄** (2026-08-05)

- 사용자 결정: "권고대로" — (c) max 인자 15.3158을 전 질의에 일괄 적용.
  corrected MDE = 15.3158 × paired_CV_fast. 안전측(false accept 불가).
- 결과: IMP-030·013·012·031은 개선이 실재해도 unprovable로 판정될 수 있다. 그 경우
  §7-e대로 기록하고, 필요 시 (d) 보정 확장을 별도 승인 작업으로 올린다.
- 사용자 질의에 대한 검증 결과(2026-08-05): "외부 CPU 간섭 ≥6 core면 불신" 규칙은
  SSOT §3-a로 **보정 측정 전체에 이미 강제되어 있었다**. 보정에 쓰인 71개 채택 블록
  (fast 36 + restart 35)의 bgload 텔레메트리 전수 확인 — 전 블록 verdict CLEAN,
  외부 부하 최대 5.88 core-s/s(< 6.0), 위반 채택 0건. 문턱 아래 간섭도 원인이 아님:
  Q01(인자 15.32)의 블록 median–외부부하 상관 r = −0.315. 인자 스프레드의 원인은
  fast 레짐 분모 CV의 분해능 바닥(Q01 0.000972, 3쌍 추정)이며, 이 규칙을 재적용해도
  결과는 비트 동일하다. 따라서 (c) 권고 유지.
- 이 결정이 실제로 가르는 후보: IMP-030, IMP-013, IMP-012, IMP-031 (+ 종결된 IMP-015).
  나머지는 어느 규칙에서도 결과 동일.

## 2. 절대 경계 (요약 — 상세는 SSOT)

- 새 IMP ID 할당 금지(§1-b, next_id=IMP-032 소진). 신규 후보는 "ID 미할당"으로 사용자
  결정 항목에 올린다.
- 스크래치는 /data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/ 하위만. /tmp·$TMPDIR 금지.
- 타 사용자 상주 프로세스 불가침(§3-b). 캠페인 소유 서버만 정지 가능.
- cubrid 명령 파이프 금지(무한 대기) — timeout + </dev/null 파일 리다이렉트.
- 장시간 작업은 tmux 자식 드라이버(§8-b). nohup·setsid·disown 금지.
- 대용량 출력은 파일로 리다이렉트 후 부분 열람.
- git rebase/reset --hard/clean -fd/force push 금지. add는 의도한 경로만.
  타 세션 미커밋 IMP-032 파일 4개(impl/IMP-032/raw-manifest.json, impl/IMP-032/report.md,
  impl/implementation-results.json, impl/notion_backfill_pending.jsonl) 불가침.
- 내구성 = origin/main 도달 가능(§1-e).
- 하니스 생성기는 제자리 실행. 검증 실행은 입력을 scratch로 복사하고 출력 경로 명시.
- state_labels.py·aggregate_baseline 핀 검사 우회 금지.

## 3. 후보 1개당 절차 (§5, §6, §7)

1. GJC 세션 1개 = IMP 1개(§8-b).
2. worktree를 frozen base 607f1ee9fb2394de129e083602c84a6525fc685c 에서 생성, 브랜치
   impl/tpch-sspq-impl-r1-20260803/IMP-NNN-<slug>. 한 브랜치 = 한 가설, 스태킹 금지(§5-b).
3. implementation-plan.md를 첫 소스 수정 전에 커밋(§5-c 10항목 전부).
4. §5-e 상류 스코프 게이트: IMP-003·022·019·011·014는 CBRD-27127/27036/27037/27094/
   27113·PR #7453 대조를 계획서에 기록. 상류가 커버하면 stop-and-report.
5. 빌드 §6-a-1 핀 레시피(INSTALL_PREFIX 필수, taskset -c 24-31, CMakeUserPresets.json
   부재 어서션, 사전 검증 6항목). 런타임 conf §6-a-2 핀(sha256 ad19f5ac…) base/patch 동일.
6. 정확성 게이트 5종 전부(§6-b). 어떤 차이도 실패 — 즉시 정지·에스컬레이션.
7. A/B §6-c: 블록마다 재기동, B→P→P→B, 블록마다 affinity·NUMA·all-TID·ownership 게이트와
   WARM 증명, 1 warmup + 3 measured, 최소 3 사이클 = 변종별 6 블록 median.
8. 통계 §6-d: paired block-median 비 + paired bootstrap 95% CI. accept는 ①에서 확정될
   결합규칙의 corrected MDE 기준. 12쌍까지 CI가 1.0 포함 시 inconclusive, 사용자 지시
   없이 쌍 추가 금지(§7-b).
9. 판정 §7-a(5조건 전부)/§7-c/§7-e. 반대 방향·2배 이상 이탈은 근본 원인 재조사 및
   원 증거 귀속 오류 가능성까지 보고.
10. 정지 조건(§5-d, §11-a): LOC 추정 150% 초과 / 예상 밖 서브시스템·XASL 직렬화·영속
    형식·락 프로토콜 접촉 / 정확성 불일치 / 통제 불가 플랜 변경 / 비표적 질의 3% 초과
    회귀 / 반대 방향 효과.

## 4. 후보별 함정 (인수 문서에서 이관)

- IMP-017은 큐에 없다 — diagnostic 레인(§4-a). IMP-016 메모리 arm의 선행 조건.
- IMP-005(enabler)는 IMP-009·IMP-012의 측정 선행 조건, 같은 176행 파일 공유 — 순서 필수.
- IMP-006·023·024는 XASL 직렬화 접촉 — §5-d 독립 hard stop.
- IMP-010·013·018은 write path — 첫 코드 전 stop-and-report(§11-a).
- IMP-021 ⊃ IMP-015, IMP-023 — 순서가 결과를 좌우.
- IMP-003/IMP-022는 같은 함수 영역 — 한 브랜치 규칙과 충돌 주의.
- IMP-030 수락 기준은 "결과 불변"일 수 없다(교체 구현이 더 정확).
- Q11 베이스라인 caveat: paired CV가 추세(-16.10% 단조)를 재고 있음 — Q11 A/B 시 노이즈
  하한을 재기동 레짐에서 재도출.
- IMP-001은 분모 미확정(BENEFIT_PENDING_DENOMINATOR)으로 랭킹 제외 유지.

## 5. 문서보다 산출물

근거는 산출물 JSON을 직접 읽는다(priority-ranking.json, fresh-baseline.json,
restart-variance-calibration.json, benefit-inputs.json). 요약 문서의 손 전사 오류가
네 세대 연속 발견된 캠페인이다. 환경 지식은 impl/CAMPAIGN-PAUSE.md §5를 그대로 적용.

## 6. 보고 규율

§8-c 상태 블록(TPCH_SSPQ_IMPL_STATUS) 주기 방출. 정지 조건 시 즉시 상태 블록 후 대기.
§11-a 에스컬레이션 항목은 반드시 사용자 결정으로 올린다.
