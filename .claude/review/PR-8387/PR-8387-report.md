# PR #8387 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8387](https://github.com/CUBRID/cubrid/pull/8387)
**제목:** [CBRD-27889] NOT EXISTS (ANTI JOIN) 와 함께 쓴 외부 조인 이후 WHERE 조건이 ANTI JOIN inner 스캔 조건으로만 평가되어 걸러져야 할 행이 남음
**작성자:** Hamkua
**HEAD SHA:** `7c76a0af734e4a67beb1f3750034ae8cbd02688c` (develop merge-base `4e389935d`)
**JIRA:** CBRD-27889 (Correct Error, Develop) / 연관: CBRD-26872 (#7907, 회귀 도입)
**TC PR:** CUBRID/cubrid-testcases#4008 (`tc/pr-8387` `4b46c011e`) / CUBRID/cubrid-testcases-private-ex#4711 (draft, 변경 파일 없음)
**리뷰 일시:** 2026-11-04
**리뷰 결정:** 엔진 PR #8387 Approve (인라인 NIT 1건, 본문 제안 1건) / TC #4008 Approve (제안 1건) / private-ex #4711 리뷰 없음

> **TL;DR** (Non-blocking): NL ANTI JOIN 이 `after_join_pred`, `if_pred` 를 짝 판정에서 빼고 짝 없는 바깥 행에 평가하도록 바뀌었고, JIRA 재현 3건과 추가 프로브 6건이 head 에서 정답, merge-base 에서 오답으로 갈렸다. 결과를 틀리게 하는 엔진 결함은 없다. 다만 memoize 키가 이제 짝 판정에 쓰이지 않는 WHERE 조건 컬럼까지 담아 ANTI inner 를 10배 더 읽는 경우가 있다 (40 miss / 4 miss). TC 는 JIRA 재현 (1) 의 RIGHT OUTER `IS NULL` 형태와 명시적 ANTI JOIN + WHERE 형태를 고정하지 않는다.

## Summary

- **변경 요약**: `qexec_execute_scan ()` 은 ANTI inner 에서 두 술어를 행마다 평가하지 않고, `qexec_execute_sa_anti_survive ()` 가 짝 없는 바깥 행에 평가한다.
- **주요 이슈**: ANTI inner memoize 키에 `after_join_pred` / `if_pred` 컬럼이 남아 miss 가 는다 (Finding 1)
- **확인 필요 사항**: TC 에 RIGHT OUTER `IS NULL` 형태와 명시적 ANTI JOIN + WHERE 형태 추가 여부

---

## Findings

### Non-blocking (should consider)

1. `src/query/memoize.cpp:357-379` (변경 없는 줄, 이 PR 로 의미가 바뀜) - memoize (같은 키의 inner 결과를 재사용하는 NL join 캐시) 의 key maker 는 inner 의 `if_pred`, `after_join_pred` 가 읽는 바깥 값을 키에 넣는다. 이 PR 이후 ANTI inner 의 두 술어는 짝 판정에 쓰이지 않고 `qexec_execute_sa_anti_survive ()` 에서 매번 새로 평가되므로, 키에 들어갈 이유가 없다. 그 결과 WHERE 조건이 LEFT OUTER inner 컬럼을 읽으면 키 종류가 그 컬럼 값만큼 늘어 inner 를 다시 읽는다.
   ```text
   head optdebug CS, t6 200행 LEFT JOIN t2 40행, NOT EXISTS t3, USE_NL
   WHERE 조건 (t2.c2 > 0 OR t6.c1 IS NULL) 있음: t3 MEMOIZE hit 1960, miss 40, t3 readrows 70
   WHERE 조건 없음                              : t3 MEMOIZE hit 1996, miss 4,  t3 readrows 7
   ```
   `XASL_NL_ANTIJOIN` 인 inner 에서는 key maker 와 `nondeterministic_check` 가 두 술어를 건너뛰면 된다. 결과 행은 두 경우 모두 1000 으로 같다.
2. `src/query/query_executor.c:11757-11780` - `after_join_pred` 블록과 `if_pred` 블록이 술어만 다른 같은 12줄이다. 두 술어를 배열로 돌거나 한 조건식으로 묶으면 한 블록으로 줄어든다. (NIT)
3. `sql/_13_issues/_26_2h/cases/cbrd_27889.sql` (TC #4008) - Case 1-4 는 모두 LEFT OUTER + OR 조건이다. JIRA 재현 (1) (RIGHT OUTER JOIN + `a0.c1 is null`) 과 명시적 `ANTI JOIN ... WHERE` 형태는 TC 에 없다. 단독 `t2.c2 IS NULL` 조건은 merge-base 에서 1, 3, 4, 5 를 내고 (정답 5) 이 PR 에서 5 를 내서, 오답 폭이 가장 큰 형태인데 TC 가 고정하지 않는다.

## JIRA -> Engine PR

JIRA 에 `design.md` / `test.md` 첨부가 없다. Expected Result 기준으로만 판정한다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| (1) RIGHT OUTER + `a0.c1 is null` -> 0 rows | merge-base 1 row (`1 1`), head 0 rows | 충족 |
| (2) LEFT OUTER + OR 조건 -> 0 | merge-base 2, head 0 | 충족 |
| (2') 명시적 ANTI JOIN -> 0 | merge-base 2, head 0 | 충족 |
| 11.4.6 과 같은 결과 | head 결과가 같은 질의의 `USE_HASH` (해시 ANTI JOIN) 결과와 모두 일치 (P4/P6) | 충족 |

PR 본문의 "ANTI JOIN 의 ON 조건은 after join term 이 되지 않는다" 는 `qo_classify_outerjoin_terms ()`, `qo_classify_antijoin_terms ()` 에서 확인했다: `QO_TC_AFTER_JOIN` 은 `!QO_ON_COND_TERM (term)` 분기에서만 붙고, ANTI 의 ON 조건은 `QO_TC_DURING_JOIN` 으로 바뀐다. 그래서 ON 조건은 여전히 짝 판정에 들어간다.

판정: 충족. CBRD-26872 는 원인 PR 로만 연관되고, 이 PR 이 닫을 별도 결함은 없다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| NOT EXISTS + 외부 조인 이후 WHERE (참/NULL/거짓 혼합) | #4008 Case 1 | 충족 |
| WHERE 에 상관 부질의 (`if_pred`) | #4008 Case 2 | 충족 |
| ANTI inner 가 파티션 테이블 | #4008 Case 3 | 충족 |
| memoize 적중 | #4008 Case 4 (plan/trace 확인은 없음) | 충족 |
| ON 조건이 세 테이블을 읽는 대조군 | #4008 Case 5 | 충족 |
| 명시적 `ANTI JOIN` + WHERE | PR 표 2행, TC 없음 | 부분 (Finding 3) |
| t3(c1) 인덱스 (idx-join) | PR 표 3행, TC 없음 | 부분 |
| NOT IN, `USE_HASH`, EXISTS, ANTI 가 앞에 오는 경우 | PR 본문, TC 없음 (모두 merge-base 에서도 정답인 대조군) | 해당 없음 |

TC 파일: case 와 answer 의 쿼리 수가 맞고, header 주석에 `;` 가 없다. Case 1-5 기대값을 데이터에서 손으로 다시 계산해 answer 와 같음을 확인했다. private-ex #4711 은 변경 파일이 없는 draft 라 리뷰 대상이 아니다 (닫으면 된다).

판정: 승인 가능. JIRA 재현 (1) 형태와 명시적 ANTI JOIN + WHERE 추가는 제안으로 남긴다 (Finding 3).

## Runtime Verification

| 출처 | 빌드 | 테스트케이스 | 결과 |
|---|---|---|---|
| gha-ci run 41757469861 | head `7c76a0af7` optdebug(debug slot) | `tc/pr-8387` `4b46c011e` | sql/medium/shell pass, `cbrd_27889` ok (108ms, shard 03) |
| 로컬 `just ctp sql _13_issues/_26_2h` | merge-base `4e389935d` optdebug CI tarball (libcubrid `8ebe311e...`) | `PR=8387` | 85 중 84 OK, `cbrd_27889` NOK: Case 1-4 에서 2, 4 가 더 나옴 (diff 8줄), Case 5 동일 -> fail-before 확인 |
| 로컬 review-only case (JIRA 재현 3건 + 프로브 6건) | merge-base / head optdebug CI tarball (head libcubrid `ef48141d...`) | develop `d10588bd4` + adhoc | merge-base: J1/J1b 1 row, J2/J3 2, `t2.c2 IS NULL` -> 1,3,4,5, OR+IS NULL -> 3,4,5. head: 모두 기대값 (0 rows, 0, 0, 5, 3,5). `USE_HASH` 와 NOT IN 은 두 빌드 같음 |
| 로컬 memoize trace 프로브 | head optdebug CI tarball, CS 서버 (port 1716, 기본값 conf + `data_buffer_size=512M`) | csql `;trace on` | 위 Finding 1 수치 |

증거: `.git_ignored_dir/scratch/pr8387/evidence/`. 각 run 은 새 서버로 시작했다.
