# 최종 보고 — 캠페인 `tpch-sspq-impl-r1-20260803` Phase 1 세션

작성 2026-08-05, head `49aa3b2` (`origin/main` 도달성 검증 완료).
규범 `tpch-sspq/IMPL-SSOT.md` @ `eccdd1ae58cd733ed3121585146d68b9ae54a73f`,
blob `15b42ddca521444fa54b34b0fa8477ed2df643f6`. **사용자 지시로 세션을 종결한다.**

---

## 1. 완료된 것 (전부 커밋·푸시·§1-e 검증 완료)

### 작업 2 — Q15 병렬 미발동 진단 (읽기 전용)

- 미발동 게이트: `external_sort.c:5232`의 `if (px == NULL || px->hash_eligible) return 1;`
  이 크기·차수 판정보다 앞서 직렬을 확정.
- 근본 원인: 병렬 heap-scan mergeable-list gather 경로에서 **리더가 튜플을 받지 않아**
  해시 패스를 실행하지 않고, `agg_hash_context->state`가 초기값 `HS_ACCEPT_ALL`에 머묾
  (`query_executor.c:27911`; 유일한 전이 `:4845`는 워커 클론 전용).
- 핵심 발견: 트레이스의 `hash: partial` 라벨은 `px_scan_result_handler.cpp:635`가 **강제
  대입**한 값. 게이트가 읽는 필드와 트레이스가 찍는 필드가 다르다.
- 재현: 동일 바이너리·데이터에서 힌트만 바꾼 4-leg 대조쌍(A/C 직렬, B/D 병렬, 라벨은 전부
  동일). 워커 page 합 대조로 병렬화된 정렬이 메인 group-by 정렬임을 정량 확정.
- 산출물: `impl/diagnosis/Q15-parallel-non-arming.md`, `q15_diag_probe.sh`.
- 파급: IMP-015의 Q15·Q18 항 반증(적용 범위가 "리더가 해시 패스를 수행하는 group-by"로
  축소), NEW-CAND-A를 ID 미할당 신규 후보로 제기.

### Phase 1A — fresh baseline (AMEND-G fast 레짐)

- Q01~Q22 전수 **131 블록 accepted / 1 invalid**, median wall 합계 **262.5440 s**
  (이전 캠페인 대비 ±0.5% 내). 전 구간 단일 인스턴스, off_sut TID 0건.
- 시도 반려 11건, 전부 `INVALID_BACKGROUND_LOAD` (Q07 2 · Q08 1 · Q09 7 · Q13 1).
- Q15 하니스 결함(AMEND-G 전환 시 세션 단위 WARM 분기 누락 → DDL을 타이밍) 발견·수정 후
  6/6 회복.

### §6-d-1 restart-variance 보정 — STOP-AND-REPORT

- 측정 인자: Q01 **15.3158** · Q02 1.4039 · Q03 1.4516 · Q04 1.4760 · Q05 2.2719 ·
  Q06 **6.4235**. 범위 비율 10.909 > 정지 비율 10.
- 단일 pooled·벽시계 의존 모두 반증(leave-one-out 2/6 임계 미달, Q03 4.539 s/1.4516 vs
  Q06 3.846 s/6.4235 직접 모순). 불안정 기전 규명: fast CV가 3-pair 추정이라 분모가
  분해능 바닥. 가법 페널티 가능성 진단 포함(가법 상대 SD 0.893 vs 곱셈 1.172).
- **인자를 고르지 않았다.** `USER_DECISION_REQUIRED`, 인자 의존 판정 전부 WITHHELD,
  세 후보 규칙별 결과 병기. 결정이 실제로 가르는 것은 5행뿐.

### Phase 1B — 랭킹·후보 큐

- **상위 5**: IMP-015 76.5 · IMP-009 72.9 · IMP-018 72.1 · IMP-014 72.0 · IMP-027 70.5.
- **큐 22개**: IMP-015 → IMP-005 → IMP-009 → IMP-018 → IMP-014 → IMP-027 → IMP-003 →
  IMP-029 → IMP-019 → IMP-023 → IMP-030 → IMP-013 → IMP-012 → IMP-031 → IMP-022 →
  IMP-016 → IMP-004 → IMP-021 → IMP-010 → IMP-008 → IMP-024 → IMP-006.
  (IMP-017은 diagnostic 레인이라 §4-a에 따라 큐 위치 없음.)
- `RANKING_UNSTABLE=True` — IMP-003↔IMP-027 구간 순서는 증거 미지지.
- 자기수정 1건: Q11 divergence +140.57%를 추적해 MD-3을 정정, IMP-018의 Q11 항을 0에서
  0.58430으로 올려 3위로. Q11 baseline caveat 기록.

### Notion 미러

- 후보 31개 중 29개 동기화(IMP-019/020은 정체 엇갈림으로 §10-f 백필).
- 진행 기록 83블록을 지정 페이지(`3b1f947f-…`) 하단에 게시, 정정 3회 전부 in-place 반영.

### 남긴 도구 (재사용 가능)

`phase1a_fast_driver.sh`(질의 단위 재개 + append 전용 확장 모드),
`aggregate_baseline.py`(paired CV 단일 출처, provenance fail-closed 핀 검사, N_BLOCKS 최소값
해석), `calibrate_restart_variance.py`(G1~G4 가드, stop-and-report), `score_ranking.py`
(`score_with()` 단일 채점기 + 민감도 base 불일치 시 실행 거부), 렌더러 2종,
**`state_labels.py`**(상태 오기 방지 fail-closed 가드, 쓰기 경로 6개 전부).

---

## 2. 품질 게이트 이력 — 정직한 기록

경계 코호트 **22세대** + 터미널 critic **5회 심사**(전부 ITERATE, ceiling 5 도달).
게이트는 실제 결함을 계속 잡았고, 그중 무거운 것:

| 잡은 것 | 성격 |
|---|---|
| 민감도 채점기가 본 채점과 다른 모집단·정렬 사용 | **실제 결함** — RANKING_UNSTABLE이 무효였다. 단일 채점기로 통합 |
| §6-d-1 인자 의존 판정을 단정 | 절차 위반 — 전부 WITHHELD로 전환 |
| baseline이 **폐기된 pre-AMEND-G 런**의 시도 무효화 16건을 게재 | **실제 데이터 provenance 결함**(§3-a 위반). 생산자 fail-closed 수정, 측정값 불변 검증 |
| 내가 권고한 (d) 절차가 no-op + `paired_cv`가 pairing 핀 때문에 재추정 불가 | 권고 철회, 규범 제약 명시 |
| 큐 23개 오기, Q01 31.65, Q09 사유 코드, Q03 4.540, 검증 문서의 파일명 날조 등 | 손 전사 오류 다수 — 전부 정정, `state_labels.py`·기계 결속 검증으로 재발 통제 |

**측정·랭킹 수치는 generation 13 이후 한 번도 움직이지 않았다** — 매 세대 수치 leaf 대조로
확인(priority-ranking 843 leaf 불변). 마지막까지 남은 결함은 전부 내 요약 서술이었다.

### 종결 시점의 미해결 채무 (은폐 없이)

- 터미널 critic 5차 심사가 완료 전에 사용자가 종결을 지시했다. 누적 non-OKAY 5회(ceiling
  도달). 4차의 blocker 2건(option (d) no-op, 프롬프트의 live 상태 박제)은 `8529cff`에서,
  generation 22의 blocker 3건(paired_cv 핀 제약, blocks_per_query 모순, 문서 과대 서술)은
  `49aa3b2`에서 수정 완료했으나 **그 수정에 대한 코호트·critic 재심사는 수행되지 않았다.**
- ultragoal 형식 상태: G001~G003 완료, G004 review_blocked, G005~G006 미착수. **사용자
  지시(authority order 1)로 종결 처리한다** — 게이트 판정을 통과한 것이 아니라 지시에 의한
  종결임을 명시한다.
- `harness/`에 상주 단위 시험 없음(코호트 QA가 매 세대 재작성해 검증했을 뿐).
- §8-e gate-artifact 경로 이탈은 공개·기록됨(정본은 허용 루트로 이전).

---

## 3. 사용자 결정 대기 (Phase 2의 입구)

**필수 2건** — 이것 없이 Phase 2 불가:

1. **§6-d-1 결합규칙**: (a) pooled 2.9598 / (b) 벽시계 의존 / **(c) max 15.3158 ← 권고** /
   (d) 보정 확장(규범 개정 + 두 레짐 대칭 재측정 선행, 비쌈). 결정이 가르는 것은 5행:
   IMP-012·013/Q08(벽시계에서만 resolvable), IMP-015/Q10·IMP-030/Q22·IMP-031/Q22(max에서만
   unprovable).
2. **Phase 1 랭킹·큐 승인** (§11-b phase gate).

**비차단 6건**: IMP-001 분모(wall/CPU), 상류 per-candidate 매핑, NEW-CAND-A ID 할당,
IMP-019/020 Notion 정체, §8-e 예외 명문화, external_tracking 종결(PR #7533, CBRD-26788).

## 4. 다음 세션 프롬프트

**`tpch-sspq/impl/HANDOFF-FINAL.md` §2**의 코드블록이 정본이다(@ `49aa3b2`, 텔레그램 전송됨).
`[[ ]]` 두 곳(결합규칙, 승인)만 채우면 그대로 사용 가능하다. Phase 2 절차 10단계, 후보별
함정(XASL hard stop 3건, write path 3건, IMP-021 순서 위험, IMP-003↔022 충돌, IMP-030 수락
기준, Q11 caveat), 보고 규율 포함.

**다음 세션에 주는 가장 중요한 조언**: 문서 서술을 근거로 쓰지 말고 **산출물 JSON을 직접
읽어라.** 이 세션에서 요약 문서의 손 전사 오류가 반복 발견됐다. 문서는 지도이고 산출물이
영토다.

## 5. 경계 준수 확인 (종결 시점)

- Phase 2 **미개시**: `git diff d5217c6..49aa3b2`에 `base-src/`·`worktrees/` 경로 0건.
- 새 IMP ID 0건: frozen registry `next_id` = `IMP-032` 유지, NEW-CAND-A는 UNASSIGNED.
- 핀 무결: `origin/main:tpch-sspq/IMPL-SSOT.md` = blob `15b42ddc…` (드리프트 없음).
- 타 세션의 미커밋 IMP-032 파일 4건 불가침 유지.
- 캠페인 소유 서버·tmux 세션 잔존 없음.
