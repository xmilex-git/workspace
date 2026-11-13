# PR #8359 코드 리뷰 보고서 (3차)

**PR:** [CUBRID/cubrid#8359](https://github.com/CUBRID/cubrid/pull/8359)
**제목:** [CBRD-27683] Stream analytic function results without intermediate list files
**작성자:** shparkcubrid
**HEAD SHA:** `4166ec0ac` (develop merge-base `36c7433d8`). 2차 리뷰 `3501715f1` 이후: develop 위로 rebase, `7e1bf7c69`(가드 추가) + `4166ec0ac`(가드 제거). `git diff aeae2b25f 4166ec0ac` 가 비어 있어 PR 코드는 2차와 바이트 단위로 같고 base 만 CBRD-27989(#8456) 위로 옮겨졌다
**JIRA:** CBRD-27683 (design.md/test.md 첨부 없음) / 연관: CBRD-27989(2차 H1 의 원인, develop `36c7433d8` 로 머지됨)
**TC PR:** CUBRID/cubrid-testcases#3978 (`tc/pr-8359` `906ae453`) / CUBRID/cubrid-testcases-private-ex#4688 (빈 draft)
**리뷰 일시:** 2026-11-11
**리뷰 결정:** 엔진 Approve(본문만), 2차 스레드 4505583216 답글 후 resolve, TC #3978 새 리뷰 없음, CCI double 출력 차이 게시 안 함

> **TL;DR** (Non-blocking): 2차의 질문(H1: 인덱스 순서로 정렬을 건너뛴 앞 그룹 + `SELECT ROWNUM`)은 작성자가 원인을 CBRD-27989 로 develop 에 고쳐 해소됐다. 이 PR 의 코드는 2차와 같고, 새 base 에서 H1 질의의 ROWNUM 이 develop 과 같은 `1..12` 다. TLA+ 는 `RESULT: OK`, TC 에 Case 14 가 추가됐고 Hamkua 의 커버리지 지적도 반영됐다.

## Summary

- **변경 요약(3차분)**: 엔진 코드 변경 없음(가드를 넣었다가 CBRD-27989 머지 뒤 뺌). TC: Case 8/10/11 을 스트리밍 경로에 머물도록 나누고(3859152fd), Case 14(SKIP_SORT + 선택된 ROWNUM) 추가(de3fe8e52)
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

(2차 Finding 2 `is_output_rec` 저장/복원은 게시하지 않기로 했고 코드도 그대로다.)

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC1 100만 건 평가 단계 시간 감소 | 본문 명령어 수 -4~-20% (wall time 미제시) | 부분(2차와 같음, 머지 차단 아님) |
| AC2 동점·NULL·다중 함수·ROWNUM 결과 동일 | 2차 근거 + H1 해소: 새 base 에서 H1 두 질의 ROWNUM `1..12`(develop 과 같음, 작성자 답글과 계측 빌드 t6 trace) | 충족 |
| AC3 대상 아닌 함수는 기존 경로 | `can_stream` default false, CUME_DIST 제외, 키 수가 다르면 제외 | 충족 |
| 대기 행 메모리 상한 | `max_agg_hash_size`, 4M행 +3.9MB 상수(2차 측정, 코드 동일) | 충족 |
| DoD RND-2589 재측정 공유 | PR 에 없음 | 미충족(머지 차단 아님) |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| ROW_NUMBER/RANK/DENSE_RANK, 동점, 다중 윈도 | #3978 Case 1-3, 2b | 통과 |
| ROWNUM select / WHERE ROWNUM | Case 5, 12 | 통과 |
| 누적·파티션 집계, FIRST/LAST_VALUE | Case 8, 9 | 통과 |
| NTILE/PERCENT_RANK 스트리밍 | Case 10 에서 CUME_DIST 를 따로 떼어 스트리밍 경로로(3859152fd, Hamkua 지적 반영) | 통과 |
| 대기 행 spill | Case 13 | 통과 |
| SKIP_SORT 앞 그룹 + 선택된 ROWNUM (2차 H1) | Case 14, 답 `1..12` 두 질의 | 통과 |

- 1차 Approve 이후 TC 변경: 3859152fd, de3fe8e52. 케이스와 답이 짝을 이루고 머리 주석에 `;` 없음. CI sql 통과(`906ae453`).
- 참고(게시 안 함 권장): sql_by_cci 에서 `cbrd_27683` 이 NOK. 차이 212줄은 모두 CCI 의 double 출력 자릿수(`1.2857142857142858` 대 `1.285714286`, `1.8999999999999995` 대 `1.9`)이고, `cbrd_27510` 등 기존 CCI 실패와 같은 종류다.

## TLA+ Verification

TLA+ 검증: 통과 — `.claude/review/PR-8359/tla/ana-stream`
- 속성: C1 결과 동일(equivalence) TLC 통과(H1 모양 `skip-rownum` 포함) / C2 메모리 상한 / C3 spill 파일 누수 없음 / C4 키 수 다른 그룹 제외 / C5 ROWNUM 출력 직전 평가 / C6 종료(liveness) 모두 통과. IndInv 귀납성 TLC `INIT IndInv`(행 3; spec 이 시퀀스를 함수로 만들어 Apalache 타입 불일치). TLAPS 요청 없음
- 결함: 없음. 2차 H1 은 base(36c7433d8, `qexec_analytic_eval_instnum_pred` 가 그룹의 `is_skip_sort` 를 봄)로 닫힘: 코드 cfg `skip-rownum` 통과, 옛 base 규칙은 `mutant-base-xasl-flag` 로 OutPrefix 위반
- mutant: 12개 모두 위반 검출(`base-xasl-flag` 추가). 살아남은 mutant: `is_output_rec` 저장/복원(2차 Finding 2, 게시 안 함)
- 경계: 행 4, 파티션 2, 정렬 키 2, AreaMax 1, 함수 2개; scale 행 5·AreaMax 2·함수 3
- trace validation: 수용 6건, 거부 3건. 계측 빌드 `4166ec0ac` + 2차와 같은 계측 스크립트, optdebug. t1~t5 는 2차 run 과 seq 외 동일, t6(H1 질의)은 이제 group 단계에서 `inum=1..12`. 거부 run 은 3차 run 에서 다시 만듦(t6 의 첫 ROWNUM 을 옛 base 값 5 로 바꾼 run 거부)
- 반례: 없음
- `RESULT: OK` (32 cfg, run `ana-stream-20261111-145204-1551206`)

## Runtime Verification

- gha-ci run 42767945629(head `4166ec0ac`, `tc/pr-8359` `906ae453`): build·sql·medium 통과. shell fail 1 = `cbrd_27571` — run 42964109559(다른 PR)에도 같은 실패, 이 PR 과 무관. sql_by_cci fail = 기존 CCI 실패 목록(8432 run 과 같은 34개) + `cbrd_27337`(최근 40개 run 중 16개에서 실패) + `cbrd_27683`(위 CCI double 출력).
- 계측 optdebug 빌드(`4166ec0ac`, `~/optdebug/CUBRID-pr8359-tla`, CS, port 1700, `max_agg_hash_size=32K`)에서 t1~t6 실행: t6(H1 질의) ROWNUM `1..12`.
- 메모리·spill 결과 비교는 2차 측정을 재사용(코드 동일).

## Existing Comments

- 2차 인라인 질문(4505583216, H1): 작성자가 CBRD-27989(#8456)로 원인을 고치고 가드를 뺐다고 답함(4521747780). 해소 확인 답글 후 해결 처리 대상.
