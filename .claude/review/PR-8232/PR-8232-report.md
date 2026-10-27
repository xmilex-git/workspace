# PR #8232 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8232](https://github.com/CUBRID/cubrid/pull/8232)
**제목:** [CBRD-27574] Keep NOT IN and <> ALL true for a NULL operand when the subquery is empty
**작성자:** shparkcubrid
**HEAD SHA:** `c9e05bf91` (develop merge-base `959314906`)
**JIRA:** CBRD-27574 (Correct Error, Open) / 연관: 없음 (본문이 언급한 CBRD-26259 는 LEFT JOIN 형태로 이미 해결된 별개 결함)
**TC PR:** CUBRID/cubrid-testcases#3831 (`tc/pr-8232` `35ad4cc97`) / cubrid-testcases-private-ex#4520 (빈 draft, develop 대비 파일 변경 없음)
**리뷰 일시:** 2026-10-22
**리뷰 결정:** 엔진 PR #8232 Approve (상위 코멘트만) / TC PR #3831 Approve (Finding 1 인라인 제안) / private-ex #4520 리뷰 없음

> **TL;DR** (Non-blocking): 두 지름길(`IS NULL`/`IS NOT NULL` 접기, NULL 상수 한정 비교 접기)을 막는 최소 수정이며 결함을 고치고 회귀는 보이지 않는다. 머지를 막는 항목은 없고, TC 에 외부 조인 열의 `IS NULL`/`IS NOT NULL` 조합 한 쌍을 더하는 것만 제안한다.

## Summary

- **변경 요약**: `qo_fold_is_and_not_null` 이 NULL 피연산자에서도 참일 수 있는 형제 항을 근거로 쓰지 않게 하고, `pt_fold_const_expr` 가 `NULL <한정 비교> (서브쿼리)` 를 접지 않게 함
- **주요 이슈**: 없음 (TC 범위 제안 1건)
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)

1. TC 범위: `qo_fold_is_and_not_null` 수정은 외부 조인이 NULL 로 채운 열에도 걸리는데 TC 는 이 조합을 검증하지 않는다. develop 에서 `tx.b IS NOT NULL AND tx.b NOT IN (빈 서브쿼리)` 가 NULL 행 1, 3 을 섞어 1, 2, 3 을 내고, 수정 빌드는 2 를 낸다. `IS NULL` 쪽은 develop 0행, 수정 빌드 1, 3. TC 의 LEFT JOIN 두 질의는 `IS NULL` 조건이 없어 이 경로를 타지 않는다.
   ```sql
   select ta.a from ta left join tx on tx.a = ta.a where tx.b is not null and tx.b not in (select b from te) order by 1;
   ```

## JIRA -> Engine PR

JIRA 에 `design.md` / `test.md` 첨부가 없고, 보고자의 시나리오 문서(`cbrd-27574_test_scenarios_20261006_1634.md`)만 있다. design 항목 행은 없다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Repro 1 Expected (`dept_id IS NULL AND dept_id NOT IN (빈)` -> id 3) | smoke: develop 0행, head 3 / TC 1번 묶음 | 충족 |
| Repro 2 Expected (`NULL NOT IN (빈)` -> 1, 2, 3) | smoke: develop 0행, head 1, 2, 3 / TC 2번 묶음 | 충족 |
| 같은 결함의 다른 형태 (`<> ALL`, `NOT (IN)`, 파생 테이블/뷰/CTE, 경로식) | TC 2, 3번 묶음, CI ok | 충족 |

판정: 충족.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| PR 표 1: `IS NULL AND NOT IN / <> ALL`, NO_UNNEST, 상관 (= JIRA TC-01) | #3831 1번 묶음 | 통과 |
| PR 표 2: `IS NOT NULL AND NOT IN (빈)` | #3831 1번 묶음 | 통과 |
| PR 표 3: NULL 상수 `NOT IN`, `<> ALL`, `NOT (IN)`, `IS FALSE`, `= ALL` (= TC-02-01~04) | #3831 2번 묶음 | 통과 |
| PR 표 4: 파생 테이블/뷰/CTE NULL 상수 열 (= TC-02-05~07) | #3831 2번 묶음 | 통과 |
| PR 표 5: 경로식 `r.a`, `r.b`, 상관 (= TC-03) | #3831 3번 묶음 | 통과 |
| PR 표 6: `IS NULL AND NOT IN` 조건 UPDATE | #3831 1번 묶음 | 통과 |
| PR 표 7: 비지 않은 서브쿼리, 리터럴 목록, `IN (빈)`, `= SOME`, LEFT JOIN, `WHERE 1 = 0` (= TC-04-01/02/04, TC-05-01/03/04/06, TC-06-01/02) | #3831 경계/UNKNOWN 묶음 | 통과 |
| PR 표 7: 호스트 변수 NULL (= TC-04-05) | TC 없음, smoke 에서 develop/head 모두 1, 2, 3 | 통과 (smoke) |
| JIRA TC-04-03/06/07, TC-05-02/05/07, TC-06-03 (`NOT EXISTS`, `UNION ALL`, 서브쿼리 NULL 포함) | JIRA 시나리오 문서. 수정이 닿지 않는 경계 | 통과 |

TC 파일 검토: 새 케이스 `cbrd_27574.sql` 의 54개 문장과 답지를 문장마다 맞춰 봤고 모두 표준 의미와 일치한다. 헤더 주석에 `;` 없음. `bug_bts_6526` 답지 갱신(빈 결과 -> `1, null`)은 서브쿼리 `c = 1 AND c <> 1` 이 빈 집합이라 맞고, 케이스 주석("MySQL and Oracle have one record")과도 일치한다. private-ex#4520 은 변경이 없어 별도 리뷰가 필요 없다. 판정: 통과 (Finding 1 은 추가 제안).

## Runtime Verification

- CI: gha-ci run 39619802893, 빌드 `c9e05bf91` debug(optdebug), TC `tc/pr-8232` (`35ad4cc97`, private-ex `319c5714`). sql 17606 / medium 975 / shell 3475 전체 pass. `_36_guava/cbrd_27574` ok, `_13_issues/_12_1h/bug_bts_6526` ok. 최신 run 39710576188 은 build 통과, 테스트 진행 중.
- smoke (리뷰어, SA 모드 `csql -S`): CI optdebug tarball 두 개, develop `959314906` 과 head `c9e05bf91`. JIRA Repro 1, 2 와 추가 probe 17개. develop 은 Repro 1, 2, 외부 조인 `IS NULL`/`IS NOT NULL` 조합, 인덱스가 있는 `IS NULL`/`IS NOT NULL` 조합, select 목록 `NULL NOT IN (빈)`, `NULL NOT IN (빈) OR ...`, DELETE 에서 틀리고, head 는 모두 기대값. 비지 않은 서브쿼리, 서브쿼리 결과에 NULL 포함, `NULL IN`, `<=> NULL`, 호스트 변수는 둘 다 같은 정답.
- 새 CTP 실행 없음: pass-after 는 CI 가 증명하고, fail-before 는 위 smoke 와 TC PR 본문의 develop NOK 기록으로 갈음.
