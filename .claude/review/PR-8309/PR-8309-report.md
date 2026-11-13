# PR #8309 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8309](https://github.com/CUBRID/cubrid/pull/8309)
**제목:** [CBRD-27376] Unnest [NOT] EXISTS / [NOT] IN subqueries over several tables into SEMI / ANTI JOINs
**작성자:** Hamkua
**HEAD SHA:** `60f29f5f8` (develop merge-base `0604b690b`, 이후 develop 의 `src/optimizer/rewriter` 변경 없음)
**JIRA:** CBRD-27376 (Improve Function/Performance, Develop) / 연관: CBRD-27379 (hash SEMI/ANTI, #8001 머지됨)
**TC PR:** CUBRID/cubrid-testcases#3916 (`tc/pr-8309` `e29aa20d4`) / cubrid-testcases-private-ex#4602 (빈 draft, 변경 파일 0)
**리뷰 일시:** 2026-10-30
**리뷰 결정:** 엔진 PR #8309 Approve (인라인 1, top-level 1) / TC PR #3916 Approve (코멘트 없음) / private-ex #4602 리뷰 없음 (빈 draft)

> **TL;DR** (Non-blocking): 서브쿼리를 비상관 파생 테이블로 감싸 SEMI / ANTI 의 inner 로 두는 변환이 정확합니다. optdebug PR 빌드에서 42개 형태(뷰, CTE, 파티션, collation, host 변수, DML 포함)가 `NO_UNNEST` 대조와 같은 결과를 냈고 assert 도 없었습니다. 남은 것은 query-wide 힌트가 파생 경로에서도 변환을 막는 점 하나입니다.

## Summary

- **변경 요약**: 서브쿼리 FROM 이 base table 여러 개인 `[NOT] EXISTS` / `[NOT] IN` 을, 바깥 참조 조건은 ON 으로, 나머지는 파생 테이블 안에 남겨 SEMI / ANTI JOIN 으로 바꿈 (`qo_rewrite_inner_as_derived ()` 신설)
- **주요 이슈**: 없음 (Non-blocking 1건)
- **확인 필요 사항**: JIRA 첨부 `design.md` 가 CBRD-27774 문서임

---

## Findings

### Non-blocking (should consider)
- `src/optimizer/rewriter/query_rewrite_subquery.c:121` — `QO_UNNEST_QUERY_WIDE_HINTS` (NO_COVERING_IDX, USE_DESC_IDX 등 질의 전체에 걸리는 힌트) 거절이 파생 경로에도 걸림 -> 파생 경로는 힌트를 밖으로 옮기지 않는데도 서브쿼리가 중첩으로 남음. 이 PR 이 같은 이유로 USING INDEX 검사를 `inner_spec->next == NULL` 분기 안으로 옮긴 것과 어긋남. 근거: `EXISTS (SELECT /*+ NO_COVERING_IDX */ 1 FROM tb, tc WHERE tb.ca = ta.cb AND tb.cb = tc.ca)` 는 중첩(`Sequential scan(ta)` 만), `/*+ ORDERED */` 는 `av1861` 로 변환 (optdebug `60f29f5f8`).
  ```c
  if (subq->info.query.q.select.hint & ~outer_hint & QO_UNNEST_QUERY_WIDE_HINTS)
    {
      return false;
    }
  ```

## JIRA -> Engine PR

JIRA 의 Specification Changes 를 기대 결과로 읽었습니다. 첨부 `design.md` (45,708 bytes) 는 제목이 "CBRD-27774: 인덱스 순서로 정렬을 생략한 분석함수가 NULL 있는 파티션에서..." 인 다른 이슈의 문서이고, `test.md` 는 없습니다. design 변경·미정 항목 행은 평가할 문서가 없습니다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 질의 결과는 변하지 않는다 | CI sql 17,680 / medium 975 케이스 pass, smoke 42개 형태 `NO_UNNEST` 대조 동일 | 충족 |
| 여러 테이블 FROM 의 [NOT] EXISTS / [NOT] IN 도 변환 | 계획에 `av1861` inner (콤마, JOIN ON, LEFT JOIN, 3 테이블, 뷰, 파티션) | 충족 |
| 파생 테이블이 한 번 실행되고 조인 순서·방식 선택에 참여 | trace `SUBQUERY (uncorrelated)`, 20,000 x 20,000 행에서 hash join 선택 (변환 0.047 s / 중첩 1.506 s, optdebug) | 충족 |
| 안쪽 조인 순서와 힌트가 파생 테이블 안에서 적용 | TC Case 4 ORDERED, smoke `USE_HASH` | 부분 (Non-blocking 1: query-wide 힌트는 변환 자체를 막음) |
| 이슈 재현 1.57 s -> 0.005 s | PR 본문 표 (작성자 측정) | 충족 (재측정 안 함) |

판정: 충족. 첨부 `design.md` 교체와 `test.md` 추가는 작성자 확인 사항.

## TC PRs

시나리오 목록 = PR 본문 "확인" 의 형태 + JIRA 재현 (JIRA `test.md` 없음).

| 시나리오 | 근거 | 판정 |
|---|---|---|
| EXISTS / NOT EXISTS (재현 형태) | #3916 Case 1 | 통과 |
| IN / NOT IN, 상관 IN | #3916 Case 2 | 통과 |
| 명시적 JOIN ... ON, LEFT JOIN | #3916 Case 3 | 통과 |
| 힌트가 안쪽에서 적용 | #3916 Case 4 (ORDERED) | 통과 |
| 변환하지 않아야 하는 경우 | #3916 Case 5 (nullable NOT IN) | 통과 |
| 안쪽 테이블끼리 조건 없음 (cross product) | #3916 Case 6 | 통과 |
| DISTINCT 대안 + 인덱스 탐색 | #3916 Case 7 | 통과 |
| 3 테이블 | TC 에 없음 (smoke Q01 로 확인) | 미충족 |
| 파티션 | TC 에 없음 (smoke Q03 로 확인) | 미충족 |

- `cbrd_27376.sql` 의 모든 질의에 답이 있고, 기존 답 4개(`cbrd_24906_1/2`, `where`, `cbrd_25776`)는 계획·rewritten query·trace 줄만 바뀜 (결과 행 변화 0).
- header 주석 20번째 줄에 `;` 가 있으나 (`NOT NULL; a correlated IN`) 답의 앞부분이 13개 문장 결과 그대로라 CTP 분할에 영향 없음.
- #4602 는 변경 없는 빈 draft -> 리뷰 대상 아님 (TC Merge Gate 상 close 필요).

판정: #3916 승인 가능. 3 테이블·파티션 케이스 추가는 선택.

## Runtime Verification

- CI (gha-ci run 40832656528, 엔진 `60f29f5f8` debug(optdebug), TC `tc/pr-8309` `e29aa20d4` / private-ex `f2fe2d1be`): sql pass(17,680), medium pass(975), shell 1 NOK `cbrd_23990_qcache_overflow` -> rerun 40843847871 pass. 이 케이스는 서브쿼리 없는 query cache 동시성 케이스이고 최근 120개 run 중 이 PR 에서만 1회.
- Lead smoke (CI tarball `builds/pr/60f29f5f8/debug`, optdebug, `libcubrid.so` sha256 `acc3526f87fe7f7e...`, `csql -S` 새 DB): `NO_UNNEST` 대조 비교
  - 22개 형태(3 테이블, 뷰, 파티션, 자기 조인, EXISTS 두 개, nullable LEFT JOIN NOT IN, `= SOME` / `<> ALL`, 바깥 참조 OR, GROUP BY, LIMIT): 결과 22/22 동일, 계획에 `av1861` 확인
  - 10개 형태(collation 다른 IN, INT vs VARCHAR/DOUBLE, PREPARE host 변수 2쌍): 10/10 동일 (INT vs VARCHAR 는 양쪽 같은 변환 에러)
  - 뷰 안 / CTE / 재귀 CTE / INSERT SELECT / UPDATE / DELETE / 스칼라 서브쿼리 안: 10개 형태, `NO_UNNEST` 대조 또는 손 계산 기대값과 동일
  - 서브쿼리 JOIN ON 안의 바깥 참조는 develop 문법 검사가 이미 거절 (`in join condition is not defined`)
  - assert, core 없음. CS 모드 서버 run 과 release 빌드는 돌리지 않음 (CI release build pass 만 확인).
- 증거: `.git_ignored_dir/scratch/pr8309/evidence/`
