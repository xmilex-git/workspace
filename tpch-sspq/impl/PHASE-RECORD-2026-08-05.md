# 구현 캠페인 tpch-sspq-impl-r1-20260803 — Phase 0·1 진행 기록과 이후 Phase 계획

기준 시각 2026-08-05. 규범은 `tpch-sspq/IMPL-SSOT.md` commit `eccdd1ae58cd733ed3121585146d68b9ae54a73f`,
blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` (1653행, AMEND-A..G). Git이 정본이고 이 페이지는
미러다(§1-a). 최신 커밋 `46be92f`, `origin/main` 도달성 검증 완료(§1-e).

## 1. 현재 상태 요약

| 항목 | 상태 |
|---|---|
| Phase 0 (규범·핀·환경) | 완료 |
| Phase 1A (fresh baseline) | **완료** — Q01~Q22 전수, 131 블록 accepted / 1 invalid |
| Phase 1B (랭킹) | **산출 완료** — 21개 performance 후보 랭킹, 후보 큐 확정 |
| §6-d-1 restart-variance 결합규칙 | **STOP-AND-REPORT — 사용자 결정 대기** |
| Phase 2 (엔진 코드 작성) | **미개시.** 엔진 소스 변경 0건, 새 IMP ID 0건 |
| Notion 미러 | 후보 31개 중 29개 동기화, 2개는 §10-f 백필 |

## 2. 작업 2 — Q15 병렬 미발동 원인 규명 (읽기 전용, 완료)

산출물 `tpch-sspq/impl/diagnosis/Q15-parallel-non-arming.md`, 재현 스크립트
`tpch-sspq/impl/diagnosis/q15_diag_probe.sh`.

**원인**: `external_sort.c:5232`의 `if (px == NULL || px->hash_eligible) return 1;`이 크기·차수·
워커 판정보다 **앞에서** 직렬을 확정한다. 그 입력을 1로 만드는 것은
`query_executor.c:5682`(IMP-015) / `:5657`(base)이고, 근본 원인은 병렬 heap scan의
mergeable-list gather 경로에서 **리더가 튜플을 한 건도 받지 않아**
(`px_scan_result_handler.cpp:628-641`) 자기 해시 패스를 실행하지 않으므로 리더의
`agg_hash_context->state`가 초기값 `HS_ACCEPT_ALL`에 머문다는 것이다
(`query_executor.c:27911`; 유일한 전이 `:4845`는 워커 클론에만 적용).

**핵심 발견**: 트레이스의 `hash: partial` 라벨은 같은 경로에서
`px_scan_result_handler.cpp:635`가 **트레이스용으로 무조건 강제 대입**한 값이다. 게이트가 읽는
필드와 트레이스가 찍는 필드가 서로 다른 필드이고 이 경로에서만 불일치한다.

**재현**: 동일 바이너리·데이터·SQL에서 스캔 병렬성 힌트만 바꾼 4 leg 대조쌍. legA(병렬스캔)=직렬,
legB(`NO_PARALLEL_SCAN`)=병렬 2워커, legC=직렬, legD=병렬 3워커. **네 leg 전부 라벨은
`hash: partial`**. 워커 page 합이 대조 leg 직렬 총량과 일치(A 19,926 ↔ B 18,300..22,522;
C 32,247 ↔ D 29,130..34,764)하여 병렬화된 정렬이 메인 group-by 정렬임을 확정했다. 계측 빌드는
필요하지 않았다.

**후보 영향**: IMP-015의 Q15 항이 반증되어 0이 되고(레지스트리는 Q15를 "armed"로 적었으나 이
경로에서 기전 발동 불가), Q18 항도 IMP-032 D1 귀속으로 대상이 메인 정렬이 아님이 드러나 0이다.
IMP-015의 검증된 적용 범위는 **"리더가 해시 패스를 수행하는 group-by"**로 좁혀진다.

## 3. Phase 1A fresh baseline (AMEND-G fast 레짐, 완료)

- Q01~Q22 전 질의 `QUERY-COMPLETE`, **131 블록 accepted / 1 블록 invalid**, median wall 합계
  **262.5440 s** (이전 캠페인 264 s와 ±0.5% 내).
- 전 구간 **단일 `cub_server` 인스턴스**(pid 3285405, start 04:59:27Z) — 전 identity 산출물에서
  pid·start_time 각 1종뿐이라 §3-c-1의 인스턴스 교체 조건 미발동. off_sut TID **0건**.
- 무효 1건은 Q09 block3 `INVALID_BACKGROUND_LOAD` — 4회 시도 모두 외부부하 최대 14.2~16.0
  core-s/s로 6.0 게이트 초과. 게이트가 오염 블록을 버린 정상 동작.
- **Q15 하니스 결함 발견·수정**: AMEND-G가 WARM을 블록 밖 질의 단위로 옮길 때
  `q15_gated_block.sh`의 세션 단위 분기를 함께 옮기지 않아 문장 단위 `warm_establish.py`가
  `create view`/`drop view` DDL을 타이밍에 섞었다(steady 0.003 s, spread 335,899%). 게이트가
  구조적으로 수렴 불가여서 Q15가 0/6이었다. 드라이버의 질의별 WARM을 Q15에 대해
  `q15_session.py`로 분기해 수정(핀 파라미터 변경 0건), 이후 steady 10.054 s로 수렴하고 6/6 확보.
  재실행은 두 번째 인스턴스(pid 3566510)에서 돌았고 그 사실이 `QUERY-COMPLETE.json`의
  `server_at_completion`에 기록된다.

주요 질의 median (s): Q01 31.65 · Q07 18.65 · Q09 10.58 · Q10 7.04 · Q11 3.23 · Q13 11.33 ·
Q15 10.02 · Q18 37.48 · Q19 43.96 · Q21 52.59 · Q22 1.12.

산출물: `tpch-sspq/impl/fresh-baseline.json`, `fresh-baseline.md`, `baseline-raw-manifest.json`.

## 4. §6-d-1 restart-variance 보정 — STOP-AND-REPORT (사용자 결정 필요)

`inflation_q = paired_CV_restart_q / paired_CV_fast_q` 측정값:
Q01 **15.3158** · Q02 1.4039 · Q03 1.4516 · Q04 1.4760 · Q05 2.2719 · Q06 **6.4235**.

**단일 pooled 인자도, 방어 가능한 벽시계 의존 인자도 맞지 않는다.**

- 벽시계 의존 모형은 강건하지 않다. 전체 표본 pearson r=0.7150이 선언 임계 0.70을 0.015로
  겨우 넘고 잔차 감축 30.1%가 임계 30%를 0.1p로 겨우 넘는데, **leave-one-out에서 Q01 제외 시
  r=+0.3928, Q04 제외 시 +0.6878**로 6개 중 2개 부분표본이 임계 미달이다. 상관이 개별 점에
  얹혀 있다.
- pooled도 범위 밖이다. 클램프 인자가 1.4039~15.3158, **비율 10.909 > 선언 정지 비율 10**.
- 모형이 직접 반증된다. **Q03(4.540 s, 인자 1.4516)과 Q06(3.846 s, 인자 6.4235)** 은 벽시계가
  1.18배 차이인데 인자가 4.43배 차이다.
- **불안정의 기전까지 규명**: 비율의 분모인 fast 레짐 paired CV가 극단 인자 질의에서 분해능
  바닥이다(Q01 0.000972, Q06 0.001123, 각각 3 pair 추정). ~0.1% 산포를 3 pair로 추정한 값을
  분모로 쓰는 비율은 안정량이 아니다.
- 추가 진단(보고만, 적용 안 함): 재기동 페널티가 **가법적**일 가능성이 더 크다. 가법 모형
  `delta = CV_restart − CV_fast`의 상대 SD 0.8930 vs 곱셈 비율 모형 1.1724. 비율이 fast CV가
  작은 곳에서 크고 큰 곳에서 작은 관측 패턴은 가법 페널티를 곱셈 추정량으로 읽을 때의 지문이며,
  그래서 max 인자 fail-safe가 정작 보정이 가장 덜 필요한 질의(Q08, fast CV 최대)를 가장 심하게
  과보정한다.

**따라서 인자를 선택하지 않았다.** 결합규칙은 `USER_DECISION_REQUIRED`이고, corrected MDE에
의존하는 `UNPROVABLE_ON_THIS_HOST` 판정은 전부 **보류(WITHHELD)** 상태로, 세 후보 규칙에서 각각
어떤 결과가 나오는지를 병기했다. 보류 12행 중 7행은 세 규칙 전부 동일(rule-invariant)이고,
**결정이 실제로 가르는 것은 5행**뿐이다:

| 후보 | 질의 | max 인자 | pooled(기하평균 2.9598) | 벽시계 의존 |
|---|---|---|---|---|
| IMP-012 | Q08 | unprovable | unprovable | resolvable |
| IMP-013 | Q08 | unprovable | unprovable | resolvable |
| IMP-015 | Q10 | unprovable | resolvable | resolvable |
| IMP-030 | Q22 | unprovable | resolvable | resolvable |
| IMP-031 | Q22 | unprovable | resolvable | resolvable |

산출물 `tpch-sspq/impl/restart-variance-calibration.json` (`STOP_AND_REPORT: true`).
`fresh-baseline.json`의 `restart_variance_correction`은 `applied: false` / `derived: true`이며,
§3-c-1의 "보정 전 baseline은 MDE 출처로 INVALID"가 **아직 해소되지 않았음**을 명시한다.

## 5. Phase 1B 랭킹 (산출 완료)

§2-b-1의 3입력 전부 사용: `feasibility-assessment.json`(불변), `triage-adjustments.json`,
Phase 1A fresh baseline. 판정과 산술을 파일 단위로 분리했다 —
`benefit-inputs.json`(후보별·질의별 효과분율·증거등급·원자료 인용, 계산 없음) /
`harness/score_ranking.py`(§2 산술, 판정 없음).

**상위 5**: IMP-015 76.5 · IMP-009 72.9 · IMP-018 72.1 · IMP-014 72.0 · IMP-027 70.5.
IMP-027이 기대절감 43.60 s로 최대이나 feasibility 41.0이 총점을 누른다.

**후보 큐** (§4-a, enabler는 의존 후보 바로 앞 위치 상속):
IMP-015 → **IMP-005** → IMP-009 → IMP-018 → IMP-014 → IMP-027 → IMP-003 → IMP-029 → IMP-019 →
IMP-023 → IMP-030 → IMP-013 → IMP-012 → IMP-031 → IMP-022 → **IMP-017** → IMP-016 → IMP-004 →
IMP-021 → IMP-010 → IMP-008 → IMP-024 → IMP-006.

**§2-d 민감도**: 증거가중 ±0.15 양방향 섭동에서 상위 5의 순서·구성이 바뀌어
**`RANKING_UNSTABLE`** 표시. pessimistic에서 IMP-027이 빠지고 IMP-003이 들어오며, optimistic에서
IMP-014↔IMP-027 순서가 바뀐다. 이 구간의 큐 순서는 증거로 지지되지 않는다.

**랭킹 제외**: IMP-001(`BENEFIT_PENDING_DENOMINATOR` — 13%가 wall인지 CPU인지 미확정),
IMP-002(`BENEFIT_CONFOUNDED`), IMP-007·IMP-025·IMP-028(`external_tracking`),
IMP-011·IMP-020·IMP-026(deferred_research), IMP-017(diagnostic, 큐 위치는 IMP-016 앞 상속 대상
아님 — §4-a에 따라 큐 위치 없음), IMP-005(enabler, 큐 위치 상속).

**방법론 판단 5건**(랭킹 보고서에 전문 수록): MD-1 CPU 수치를 wall 분모에 대입하지 않는다 /
MD-2 레지스트리가 CPU→wall 환산을 제시한 경우에만 환산하고 인용한다 / MD-3 WARM 레짐 밖 효과
판정은 이 캠페인 자신의 베이스라인으로 검증한다 / MD-4 PostgreSQL 수치는 achievable floor
논증으로만 쓴다(§3-d) / MD-5 합성 프로브 측정을 논증 없이 실제 질의로 이관하지 않는다.

**이 실행이 스스로 찾아낸 자기수정**: §3이 요구하는 이전 캠페인 대비 divergence 비교에서
**Q11이 +140.57%**로 스윕 최대 이탈을 보였다. 설명 과정에서 초안 MD-3의 IMP-018 처리(기대절감 0)가
반증되었다 — fresh median 3.2285 s는 이전 캠페인의 saturated 1.342 s가 아니라 IMP-018이 측정한
`connection_1_of_the_query` 3.544 s의 9% 안에 있고, Q11 블록 median이 3.529→2.961로 **단조
감소**하는 연결 간 감쇠 지문을 보이며(Phase 1A는 블록마다 새 `csql -C` 연결을 연다,
`headline_run.py:189`), Q11은 22개 질의 중 단조 드리프트 3% 초과가 **유일**하다. IMP-018 항을
0에서 보수적 0.58430으로 정정해 순위 3위로 올렸고, Q11 베이스라인에는 caveat를 붙였다(블록이
교환가능 표본이 아니라 추세이므로 paired CV가 추세를 재고 있고, 노이즈 하한은 Phase 2의 재기동
레짐에서 재도출해야 한다).

산출물 `tpch-sspq/impl/priority-ranking.json`, `priority-ranking.md`(§2를 핀된 IMPL-SSOT에서
렌더 시점에 바이트 단위로 추출해 수록, §2-e 12열 정확 일치).

## 6. 품질 게이트 이력 (참고)

경계 완료 코호트를 **12세대** 돌렸다. cleaner·architect·QA 세 레인이 매 세대 동일 frozen
`sourceHash`에 결속되어 심사했고, 실제 결함을 다수 잡았다: §4-a 큐 위치 규칙 위반(diagnostic
IMP-017이 큐에 들어가고 enabler IMP-005에 모순 문구), §2-e 표의 데이터 행이 13열이던 문제,
그리고 터미널 critic이 2회 ITERATE로 잡은 **민감도 채점기가 본 채점과 다른 모집단·정렬을 쓰던
결함**(`RANKING_UNSTABLE`이 무효였다)과 **§6-d-1 인자 의존 판정을 단정하던 절차 위반**.

"상태 의존 문구를 상태로 조건화하지 않음" 결함이 아홉 번 반복되고 매번 그 시점 delta 밖이라
리뷰가 놓쳤으므로, 통제 수단을 리뷰에서 생성기로 옮겼다 — `harness/state_labels.py`가 생성기
산출물을 상태별 금지 문구 목록과 대조해 **모순하는 출력을 거부**한다. 쓰기 경로 6개 전부 가드
아래 있다.

## 7. 사용자 결정 대기 항목 (Phase 2 개시 전 필요)

1. **§6-d-1 결합규칙 선택** — pooled(기하평균 2.9598) / 벽시계 의존 / max(15.3158) / **보정 블록
   추가 수집**(분모 불확실성을 모형 선택이 아니라 측정으로 줄이는 길, 권장 검토). 위 5행의 판정이
   여기서 갈린다. 이 결정 전에는 Phase 2 accept 판정에 쓸 corrected MDE가 확정되지 않는다.
2. **Phase 1 랭킹·후보 큐 승인** — §11-b/Phase gate. 승인 없이 Phase 2 개시 금지.
3. **NEW-CAND-A ID 할당 여부** — 작업 2가 찾아낸 신규 후보. §1-b에 따라 새 IMP ID를 할당하지
   않았다(`next_id`는 `IMP-032`로 소진). 성능 arm과 측정정확성 arm을 한 후보로 볼지 둘로 나눌지도
   결정 필요.
4. **IMP-019 / IMP-020 Notion 정체** — 두 페이지의 `IMP ID` auto_increment 번호와 제목 접두가
   서로 엇갈려 있다(unique_id=19의 제목이 `IMP-020: …`, unique_id=20의 제목이 `IMP-019: …`).
   정본은 Git의 frozen registry이고 Notion은 미러이므로 추측하지 않고 보류했다. §10-f 백필
   레코드에 페이로드 전문이 있어 정체 확정 후 재생하면 된다.
5. **§8-e gate scratch 경로 예외 명문화 여부** — 완료 게이트 검증기가 artifact 경로를 저장소
   아래로 제한해 브리프 허용 루트와 배타적이었다. 정본은 허용 루트로 이전했고 이탈을 기록했다.
   §6-a-2의 `work/tmp` 예외와 같은 형식으로 명문화할지 결정 필요.
6. **IMP-001 분모** — 프로토타입 ~13%가 wall인지 CPU인지. 이 한 datum 없이는 점수·순위 불가.
7. **상류 티켓 per-candidate 매핑** — CBRD-27127/27036/27037/27094/27113, PR #7453이 set-to-set로만
   기록되어 IMP-003/022/019/011/014가 여섯 건 전부에 대해 게이트된다. per-candidate 매핑이 있으면
   게이트가 좁아진다.
8. **`external_tracking` 종결(OQ-F4)** — PR #7533 병합 여부(IMP-025, IMP-028), CBRD-26788 해결
   방식(IMP-007) 확인이 캠페인 종결 전 필요.

## 8. Phase 2 계획 (승인 후 수행, 규범 §5·§6·§7)

**전제**: 위 1·2번 결정. corrected MDE가 확정되지 않으면 §7-a criterion 3(점 개선 ≥ MDE)을
판정할 수 없다.

후보 하나당 다음 순서를 지킨다.

1. **GJC 세션 1개 = IMP 1개**(§8-b). Phase 1A의 단일 드라이버 예외는 Phase 1A 한정이다.
2. **워크트리·브랜치**: `worktrees/IMP-NNN`을 frozen base SHA `607f1ee9fb2394de129e083602c84a6525fc685c`
   에서 생성, 브랜치 `impl/tpch-sspq-impl-r1-20260803/IMP-NNN-<slug>`. **한 브랜치 = 한 IMP = 한
   가설**, 패치 스태킹 금지(§5-b).
3. **`implementation-plan.md`를 첫 소스 수정 전에** 후보 브랜치에 커밋(§5-c, 10개 항목: 반증 가능한
   가설 / 변경할 CUBRID `file:line` / PostgreSQL 참조 `file:line` / 예상 변경 파일과 LOC 밴드 /
   움직여야 하는 지표 signature와 방향 / 정확성 위험과 시험 방법 / 표적 질의 / 음성 대조 질의 /
   중복·의존 관계 / 롤백 방법).
4. **§5-e 상류 스코프 게이트**: IMP-003·022·019·011·014는 첫 소스 수정 전에 상류 티켓·PR 대조
   결과를 `implementation-plan.md`에 기록. **상류가 이미 커버하면 stop-and-report**이며 병행 진행이나
   범위 축소 사유가 아니다.
5. **빌드**: §6-a-1 핀 레시피 그대로. `INSTALL_PREFIX` 지정 필수(`~/CUBRID` 재지정 금지),
   `taskset -c 24-31 just build release`, `CMakeUserPresets.json` 부재 어서션, 사전 검증 6항목.
   런타임 conf는 §6-a-2 핀(sha256 `ad19f5ac…`)을 base와 patch에 **동일**하게 설치.
6. **정확성 게이트 5종 전부**(§6-b): 후보 특화 단위·회귀 시험 / 표적 질의 / `q_relations` 전 질의 /
   Q01~Q22 결과 스모크 / 동시성·메모리 후보는 별도 스트레스·진단 빌드(성능 레짐 밖). **어떤 차이도
   실패**이며 즉시 정지·에스컬레이션.
7. **A/B 측정**(§6-c, Phase 1A와 달리 **블록마다 재기동**): `B → P → P → B`, 블록마다 affinity·NUMA·
   all-TID·ownership 게이트 통과와 WARM 증명, 1 uncounted warmup + 3 measured. 최소 3 사이클 =
   변종별 6 블록 median.
8. **통계**(§6-d): 주 추정량은 paired block-median P/B 비, CI는 paired bootstrap 95%,
   **accept는 corrected MDE 기준**(§6-d-1). 12 pair까지 CI가 1.0을 포함하면 `inconclusive`이며
   사용자 지시 없이 pair 추가 금지(§7-b).
9. **판정**(§7-a accept 5조건 전부 / §7-c reject 조건 / §7-e 예상 밖 결과는 은폐 금지, 반대 방향이나
   2배 이상 이탈은 근본 원인 재조사).
10. **정지 조건**(§5-d, §11-a): 실제 변경이 high-LOC 추정의 150% 초과 / 예상 밖 서브시스템·XASL
    직렬화·영속 형식·락 프로토콜 접촉 / 정확성 불일치 / 계획 밖 A/B 플랜 변경 / 비표적 질의 3% 초과
    회귀 / 반대 방향 효과.

**후보별 특이 주의**

- **IMP-015**(큐 1위)는 이미 구현·측정되어 `accepted (provisional)`이다. 재구현 대상이 아니라
  적용 범위 축소(작업 2 결과)를 반영해 재검토할 대상이다.
- **IMP-005**(enabler)는 IMP-009·IMP-012의 측정 선행 조건이며 같은 176행 파일을 공유하므로
  순서를 지켜야 한다.
- **IMP-006·IMP-023·IMP-024**는 **XASL 직렬화**를 건드린다 — §5-d 독립 hard stop.
- **IMP-010·IMP-013·IMP-018**은 **write path** — §11-a에 따라 첫 코드 한 줄 전에 stop-and-report.
- **IMP-021 ⊃ IMP-015, IMP-023**: IMP-021이 먼저 들어가면 앞의 둘이 가속하려는 워크로드 자체가
  사라진다. 순서가 결과를 좌우한다.
- **IMP-003 / IMP-022**는 같은 함수 영역을 수정해 한 브랜치 규칙과 충돌한다.
- **IMP-030**의 수락 기준은 "결과 불변"일 수 없다 — 교체 구현이 현행 문자열 왕복보다 **더 정확**하다.
- **IMP-011·IMP-014**는 증거가 건전하다고 트리아지가 확인했으나 상류 스코프 게이트에서 면제되지
  않는다. 둘 다 유지된다.

## 9. Phase 2 이후 (§11-b 종결)

1. 승인된 큐의 모든 IMP가 `accepted`/`rejected`/`inconclusive` 중 하나와 결정 기준을 갖는다.
2. `implementation-results.json`에 accepted·rejected·inconclusive **브랜치 목록**을 공표한다.
3. 결과별 Git·raw·Notion 정합성 검증: 모든 report commit이 `origin/main`에서 도달 가능, raw
   manifest artifact 해시 존재, Notion 행 동기화 또는 백필.
4. **사용자 승인 후** frozen base SHA에서 accepted 후보를 담은 누적 브랜치 생성.
5. 누적 브랜치의 base 대비 **Q01~Q22 정확성** 실행(§6-b 규칙).
6. **누적 성능 A/B**(§6-c/§6-d 레짐).
7. 최종 report·raw manifest 커밋·푸시·도달성 검증.
8. 캠페인 GJC 세션·tmux 세션·프로세스 전부 부재 검증.
9. **상류 브랜치 병합은 별도 사용자 승인 대기.** 누적 브랜치 생성이 병합 허가가 아니다.

## 10. 환경 수칙 (재발견 금지)

`cubrid` 명령 파이프 금지(무한 대기) — `timeout`과 `</dev/null`로 파일 리다이렉트.
SUT/클라이언트 CPU `0-15` + `--membind=0`, collector `20-23`, 컨트롤러·빌드 `24-31`, `16-19` 분리대.
affinity는 래퍼를 감싸야 한다(`resources.cpp:190`이 서버 시작 시 마스크를 function-local static에
캐시하므로 사후 `taskset`은 원리적으로 불가). 외부부하 게이트 6.0 core-s/s는 측정으로 정한 값이며
호스트 상시 외부부하는 mean 1.94 / p95 10.02 / max 16.03 core-s/s다. 스크래치는
`/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/` 하위만 — `/tmp`·`$TMPDIR` 절대 금지.
장시간 작업은 tmux 자식 드라이버로(`nohup`·`setsid` 금지). 타 사용자 상주 프로세스 불가침.
