# PR #8085 코드 리뷰 보고서 (2차)

**PR:** [CUBRID/cubrid#8085](https://github.com/CUBRID/cubrid/pull/8085)
**제목:** [CBRD-27543] Skip NL join memoize when statistics show the outer key hardly repeats
**작성자:** shparkcubrid
**HEAD SHA:** `405422e0e` (develop merge-base `8e79ac3da`, #8051 포함. 그 뒤 develop 4커밋은 memoize와 무관)
**JIRA:** CBRD-27543 (Improve Function/Performance, Confirmed) / 연관: CBRD-27487 (PR #8051, 머지됨. 실행 중 판단 정책이며 같은 결함 아님)
**TC PR:** CUBRID/cubrid-testcases#3627 (`tc/pr-8085` `89d377226`) / CUBRID/cubrid-testcases-private-ex#4298 (draft, develop 머지 커밋 `3a527f9ef`만, 파일 변경 없음)
**리뷰 일시:** 2026-10-10 (1차 2026-10-08 `380d10ad9`, 엔진·TC 모두 Request changes. `PR-8085-report-20261008.md`)
**리뷰 결정:** 엔진 PR #8085 Approve / TC PR #3627 Approve / private-ex #4298 리뷰 없음 (변경 없음). 게시 지적 없음

> **TL;DR** (Non-blocking): 1차 리뷰 지적이 모두 반영되었다. NULL 허용 unique 키 가드(`405422e0e`), 3-repo 동기화 후 CI 통과, TC 답지 갱신과 케이스 2개 추가, TPC-H / JOB 측정까지 끝났다. 남은 것은 PR 본문이 마지막 커밋과 TC 추가를 반영하지 않은 점이다.

## Summary

- **변경 요약**: 통계로 outer 키가 거의 반복되지 않는다고 판단한 NL inner에 `XASL_NO_MEMOIZE`(memoize 저장소를 만들지 말라는 XASL 플래그)를 설정. 1차 이후 코드 변경은 NOT NULL 가드 커밋 1개이고, 나머지 8커밋은 rebase만 되었다(range-diff 동일).
- **주요 이슈**: 없음 (PR 본문 갱신 1건)
- **확인 필요 사항**: 없음 (JIRA DoD의 매뉴얼 항목은 "따로 진행"으로 이미 답변됨, comment 6051630311)

---

## Findings

### Non-blocking (should consider)

- PR 본문의 판단 조건이 코드와 다르다. 본문 Implementation은 "PK·unique 인덱스의 단일 컬럼(... NDV = 행 수로 취급)"이라고 적었다. 코드는 NOT NULL인 컬럼에만 행 수를 쓴다. `QO_SEG_IS_NOT_NULL`(컬럼에 NOT NULL 또는 PK 제약이 있으면 참, `qo_insert_segment ()`가 설정)이 그 조건이다.
  ```c
  if (qo_seg_has_unique_index (seg) && QO_SEG_IS_NOT_NULL (seg))   /* query_planner.c:3971 */
  ```
  같은 본문 Remarks는 상속 계층 재현을 "TC에 넣지 않고 수동으로 확인"했다고 적었다. 하지만 #3627 `89d377226`에 그 케이스가 들어갔다. TC 표에는 NULL 허용 unique 키 행(유지)이 없다. 본문은 이 PR의 설계 기록이다. 그대로 머지되면 본문으로 판단 조건을 확인하는 사람은 NULL 조건을 놓친다. (grill: 보고서에만 남기고 게시하지 않음)

## JIRA -> Engine PR

기준: JIRA Acceptance Criteria(AC)가 재현 조건에서 성립하고, JIRA Implementation의 변경이 구현되었거나 이탈 사유가 있고, Definition of Done(DoD)이 정리되었는가. JIRA에 design.md / test.md 첨부가 없어 본문으로 판정한다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC: 고유 키(통계 있음)에서 저장소 미생성 | TC 케이스 1, 2, 4 (CI ok, develop은 MEMOIZE 출력). TPC-H / JOB에서 생략된 inner의 실제 hit가 모두 0 (comment 6052608747) | 충족 |
| AC: 주기 키, hot/cold, NDV 2000 키 유지 | 1차와 같은 코드. TC 저 NDV 키 케이스, PR 성능표 | 충족 |
| AC: 통계 없는 테이블은 현재 동작 | TC 케이스 3 (#8051 이후 develop과 같은 MEMOIZE 출력) | 충족 |
| AC: 직렬과 PARALLEL(N) | TC 케이스 2 (parallel 4) | 충족 |
| AC: memoize on/off 결과 동일 | TC on/off 블록, TPC-H 15/15, JOB 103/103 | 충족 |
| Impl: 추정이 불확실하면 플래그 없이 실행 중 판단 | NULL 허용 unique 컬럼은 95% NDV 규칙으로 판단 (`405422e0e`) | 충족 (1차 Blocking 해결) |
| Impl 나머지 / 검토(미정) 항목 | 1차와 같은 코드. 키 NDV, 캐시 용량 항 제외, 플래그 직렬화, 조인 outer, 힌트 미도입 모두 1차 판정 유지 | 충족 |
| DoD: CTP 케이스, 기존 memoize TC 재확인 | #3627, CI에서 cbrd_26345, cbrd_27487, cbrd_27465, cbrd_25519 ok (#8051 포함 base) | 충족 |
| DoD: TPC-H / JOB 회귀 없음 | comment 6052608747: TPC-H SF1 -0.5%, JOB -0.2%, 증가한 질의 없음, 결과 일치 | 충족 |
| DoD: 매뉴얼 | "따로 진행하겠습니다" (comment 6051630311) | 미충족 (별도 진행) |

판정: 충족. 매뉴얼만 별도 진행으로 남았다. CBRD-27487은 #8051로 해결된 다른 이슈이고, 이 PR의 대상이 아니다.

## TC PRs

기준: 시나리오는 엔진 PR 검증표의 행이다(JIRA test.md 없음). TC PR이 언급하면 통과다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 거의 고유 키, 통계 있음 (직렬 / PARALLEL / LEFT JOIN inner) -> 생략 | #3627 케이스 1, 2, 4. develop `1386afc02`에서 NOK | 통과 |
| 같은 키, 통계 없음 -> 실행 중 판단 | 케이스 3, #8051 이후 MEMOIZE 출력으로 갱신 | 통과 |
| NDV 300 키, fact JOIN dim, dim JOIN fact, fan-out 10 -> 유지 | 케이스 5, 7, 8, 6 | 통과 |
| 행만 줄이는 조인 outer, 분할 outer / inner -> 생략 | 케이스 9, 10, 11 | 통과 |
| 뒤에 분할 테이블이 붙은 inner -> 실행 중 판단 | 케이스 12, MEMOIZE 출력으로 갱신 | 통과 |
| NULL 90%인 unique 키 -> 유지 (1차 Blocking) | 새 케이스. `380d10ad9`에서는 MEMOIZE 없음(1차 probe B1, 같은 SQL) | 통과 |
| 상속 계층 outer, 클래스 간 같은 키 -> 유지 (1차 TC 2) | 새 케이스 | 통과 |
| PK 재조회 inner 생략 (cbrd_24252_5 답지 변경) | #3627, develop NOK / head ok | 통과 |

TC 파일: 바뀐 답지 2개와 새 케이스 2개 모두 답지가 맞고(CI ok), 헤더 `--` 주석에 `;`로 끝나는 줄이 없다. 1차 TC 1(답지), TC 2(상속 계층), TC 3(95%)이 모두 반영되었다.

판정: 통과. #4298은 파일 변경이 없어 리뷰하지 않는다(닫기는 TC Merge Gate 봇이 이미 안내).

## Runtime Verification

- CI: gha-ci run 37728573418. head `405422e0e` optdebug, TC `tc/pr-8085` `89d377226`(shell은 private-ex `3a527f9ef`).
  - sql 17492, medium 975 통과. cbrd_27543, cbrd_24252_5, cbrd_26345, cbrd_27465, cbrd_27487, cbrd_25519 ok.
  - shell 3293건 중 `_06_issues/_26_1h/cbrd_26564` 1건 NOK. 10-08 develop에 들어온 TC로, 6개 PR의 run 14개 중 8개에서 실패한다. 이 PR과 무관.
  - Check TC PRs 실패는 TC PR이 아직 머지되지 않아 TC Merge Gate가 막은 것이다(정상).
- 1차 증거 재사용:
  - develop `1386afc02`(#8051 포함)에서 cbrd_27543 케이스 1, 2, 4에 MEMOIZE가 나왔다(fail-before). `1386afc02..8e79ac3da`에 memoize 관련 변경은 없다(#8058은 병렬 GROUP BY 도메인).
  - probe B1은 새 NULL 케이스와 같은 SQL이다. `380d10ad9`에서 MEMOIZE가 없었다. 새 케이스가 가드를 고정한다.
- 새로 돌린 실행 없음. 증거: `.git_ignored_dir/scratch/pr8085/evidence/r2/ci-37728573418.txt`.
