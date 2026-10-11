# PR #4351 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4351](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4351)
**제목:** [CBRD-27365] Revise for shell_perf tc
**작성자:** ssihil (리뷰어 지정: xmilex-git, kwonhoil)
**HEAD SHA:** `21dd9416d` (develop merge-base `6cb1a3b18`; 이후 develop 커밋은 무관한 revert #4352 1건)
**JIRA:** CBRD-27365 (엔진 #7866 `453da49c8`, build 2625) / 연관 CBRD-27140 (`519cc1a43`, build 2567), CBRD-25454, CBRD-25717/26666
**리뷰 일시:** 2026-10-08
**리뷰 결정:** COMMENT 게시 (review 5454070276, 2026-10-08; 본문 + 인라인 4건). 사용자: split_scaling 해석을 사전 확인해 준 적 없음 → 개발자 확인 문구 정정 요청 포함. cbrd_25454 2625 vs 2647 추가 측정은 생략.

> **TL;DR**: 스크립트 로직은 맞다. split_scaling 은 degree 8 해석은 맞지만 degree 12/16 이 CBRD-27365 에서 느려졌고(15→19ms), 원인은 새 포맷에서 split 작업 단위가 8개 남짓으로 줄어든 것(데이터 3배면 다시 확장됨) — 합격선 3.2x 하향보다 데이터 3배 + 기존 4.0x 유지가 맞다. cbrd_25454 는 11% 여유 근거가 2647 3회뿐이고 PR 본문의 원인 설명이 JIRA 10/07 측정과 다르다.

## 바뀐 것
1. cbrd_25454.sh: cur/old 각 3회 중앙값, `bc scale=2`, `bc` 비교, pass_pct 15 → 11.
2. cbrd_25717_split_scaling.sh: 헤더 수치 2565 → 2647, 8워커 기준 4.0x → 3.2x (`t1*10/32`), 정체 시작 12 → 8.

## 스크립트 검증 (정적)
- `median`: RUNS=3 → v[2]. 빈 측정값 → bc 오류 → 빈 문자열 → `[ "" -eq 1 ]` 실패 → NOK. 정상.
- `bc` 관계식은 GNU bc 확장(CTP 러너는 GNU bc). 정상.
- split_scaling 정수 산술: t1=74 → limit 23, t8=19 통과. 정상.

## split_scaling A/B (이 호스트, `.git_ignored_dir/scratch/p4351/report.md`)
32코어 공유 호스트, release 2565/2624/2625/2647, 차수별 5회 최솟값, 2라운드(순서 반전), 서버 maps 로 libcubrid 확인. TC 단정 방식 그대로 에뮬레이션 시 8세트 모두 PASS.

| build | d1 | d4 | d8 | d12 | d16 | SPLIT fetch d1 / d8 / d12 / d16 |
|---|---|---|---|---|---|---|
| 2565 | 100 | 31 | 20 | 14 | 14 | 5838 / ~7000 / 7461 / 7848 |
| 2624 | 110 | 31 | 18 | 15 | 15 | 5838 / ~7000 / 7461 / 7848 |
| 2625 | 93 | 27 | 18 | 19 | 19 | 967 / 1632 / 1632 / 1632 |
| 2647 | 88 | 25 | 19 | 19 | 19 | 967 / 1632 / 1632 / 1632 |

3배 데이터(900k/600k/300k): 2624 = 396/109/62/53/48 (3.63/6.39/7.47/8.25x), 2647 = 295/79/52/39/41 (3.73/5.67/7.56/7.20x), SPLIT fetch 2647 d8/d12/d16 = 6955/12286/14974.

판정:
- 직렬 감소(110→93)와 d8 유지(18→18)는 CBRD-27365 단독 효과 — PR 의 "분모가 줄었다"는 d8 에서 맞음.
- d12/16 은 2625 에서 15→19ms 악화 — 헤더 "parallel floor stayed ... not because the parallel path got slower" 는 d8 에만 맞음.
- 새 포맷에서 SPLIT fetch 가 d8 이후 고정(1632) → 추가 워커가 일을 못 받음(추론; trace 에 섹터 수는 안 나옴). 3배 데이터에서 다시 확장되므로 "고정 비용" 설명보다 "작업 단위 부족" 이 맞다.
- CBRD-27365 Spec Changes("리스트 페이지 수로 내리는 결정이 바뀐다")와 일치.

## cbrd_25454
- 여유: 2647 cur 41.33s(3회) 기준 13.74~14.38%. 그러나 PR 본문 2차 / JIRA 10/07 QA 수치로 2625~2632 cur 42.2~42.6s → old 48.0s 기준 11.3~12.1%, 여유 0.3~1.1%p. 2647 이 1.2s 빠른 이유(이후 커밋 vs 측정 방식) 미확인.
- 헤더 Test/Result 가 20% / 30~40% 그대로 (변경 전에도 15% 와 불일치).
- PR 본문 CBRD-27365 원인 설명 vs JIRA 10/07 측정(`.git_ignored_dir/scratch/cbrd27365-perf/report.md`): 250M temp 리스트 없음(임시 페이지 0), 증가분은 슬롯 바인딩(+11 instr/row), fetch_val_list 동일, "압축" 아님, 15% 미달은 1차부터.
- JIRA 10/08 코멘트 "2596-5d8fc7b / CBRD-27410" vs PR "2567-519cc1a / CBRD-27140": 5d8fc7b = CBRD-27326, CBRD-27410 커밋 없음.

## 후속
- 작성자 답변 대기: split_scaling 데이터 3배 여부, 헤더 원인/개발자 확인 문구 정정, cbrd_25454 여유 근거(2625/2632 분포), 헤더 기준, JIRA 10/08 코멘트의 2596/CBRD-27410 표기.
