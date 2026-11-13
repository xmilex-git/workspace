# PR #8335 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8335](https://github.com/CUBRID/cubrid/pull/8335)
**제목:** [CBRD-27468] Use GROUP BY skip for GROUP BY ... WITH ROLLUP
**작성자:** shparkcubrid
**HEAD SHA:** `e33868668` (develop merge-base `cd341a6d6`)
**JIRA:** CBRD-27468 (Improve, Analysis) / 연관: CBRD-27467, CBRD-27664(#8207, 머지됨), CBRD-27728
**TC PR:** CUBRID/cubrid-testcases#3947 (`tc/pr-8335` `389c328ab`) / cubrid-testcases-private-ex#4647 (`17ac99296`)
**리뷰 일시:** 2026-10-30
**리뷰 결정:** 엔진 PR #8335 Approve (top-level에 질문 1건) / TC PR #3947 Approve / TC PR #4647 Approve

> **TL;DR** (Non-blocking): 엔진 변경에서 결함을 찾지 못했다. 정렬 GROUP BY의 ROLLUP 마무리 로직을 레벨 인자로 분리해 직렬·병렬 skip이 같이 쓰고, head와 develop 결과가 SA 12개 질의·티켓 질의 모두 같다. PR 성능 표의 `ORDER BY 키 LIMIT 5` 행은 develop과 이 PR이 같은 틀린 답(총계 행 누락)을 내는 질의라 별도 이슈로 다루자고 질문한다.

## Summary

- **변경 요약**: 옵티마이저의 ROLLUP 제외 3곳을 빼고, GROUP BY skip(인덱스 순서로 그룹을 받아 정렬 없이 집계하는 경로)에서 첫 불일치 키 위치로 ROLLUP 소계를 마무리
- **주요 이슈**: 없음
- **확인 필요 사항**: `ROLLUP + ORDER BY 키 LIMIT` 결과가 develop부터 틀림(총계 행 누락). 성능 표 행 처리와 별도 이슈 등록 여부

---

## Findings

### Questions for the author
- PR 본문 성능 표 `ROLLUP + ORDER BY 키 LIMIT 5` (0.410s -> 0.074s) — 이 질의는 develop과 head 모두 총계 행 `(NULL, NULL)`을 빠뜨린다. `ORDER BY g, v` 없이 LIMIT을 빼면 총계 행이 첫 행(ASC는 NULL 먼저)으로 나오는데, `LIMIT 3`을 붙이면 develop 힙 스캔 경로(`ignore index`)도 `(0,0),(0,1),(0,2)`를 돌려준다. PR이 만든 결함은 아니지만(develop 동일, P12) 5.5배 이득이 틀린 답 위에서 잰 값이다. 본문 표에서 빼거나 주석을 달고, LIMIT이 ROLLUP 소계 위에서 ORDER BY보다 먼저 걸리는 문제는 별도 이슈로 등록하는 것이 맞는지.
  ```
  select g, v, count(*) from t_roll ignore index (i_gv, i_hg) where g >= 0
    group by g, v with rollup order by g, v limit 3;   -- develop/head: (0,0) (0,1) (0,2), 기대: (NULL,NULL) (0,NULL) (0,0)
  ```

## JIRA -> Engine PR

JIRA에 `design.md`/`test.md`/`test_result.md` 첨부가 없다(다른 팀 PR이라 코멘트에는 올리지 않음, P19). 기준은 티켓 본문의 Acceptance Criteria와 Implementation.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC1 티켓 질의가 인덱스 스캔 + skip GROUP BY, trace `sort: false` | SA head: `Index scan` + `skip GROUP BY` (develop은 `Sequential scan`). trace는 TC Case 1-3 답안 | 충족 |
| AC2 결과 행·순서가 정렬 ROLLUP과 같음, 105행 | SA 티켓 질의 head/develop 105행, 결과 블록 diff 0줄 | 충족 |
| AC3 인덱스와 GROUP BY 순서 불일치 시 정렬 경로로 폴백 | TC Case 8 (`group by v, g`, DESC) `hash: true, sort: true` | 충족 |
| 구현: 실행기 nosort 경로에 ROLLUP 소계, 정렬 경로 로직 재사용 | `qexec_gby_finalize_group_level` 분리. 정렬 경로 반환값·마무리 레벨은 기존과 같음(호출자 `qexec_gby_put_next`는 `with_rollup`일 때만 사용) | 충족 |
| 구현: 옵티마이저 `!with_rollup` 조건과 assert 제거 | 3곳 제거, 역방향 skip만 ROLLUP 제외 | 충족 |
| DoD: 기존 ROLLUP TC(CBRD-25611/25686/25746/26215/26227) 통과 | gha-ci test_sql 17693건 pass | 충족 |

연관 이슈: CBRD-27728(GROUP BY DESC 직렬 역방향 skip)은 이 PR이 고치지 않는다. PR이 본문에서 별건으로 밝힘.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 2키 커버링 병렬·직렬 | #3947 Case 1, trace `parallel workers` 줄 | 통과 |
| 비커버링 병렬, AVG 병합 | #3947 Case 2 | 통과 |
| 1키, 3단계 | #3947 Case 3 | 통과 |
| NULL 그룹 키와 소계 구분 | #3947 Case 4 | 통과 |
| HAVING, ORDER BY | #3947 Case 5 | 통과 |
| DISTINCT·GROUP_CONCAT·MEDIAN | #3947 Case 6 | 통과 |
| 빈 범위, 단일 키 범위 | #3947 Case 7 | 통과 |
| DESC·순서 불일치 폴백 | #3947 Case 8 | 통과 |
| 플랜 표시 변경(`SORT (group by)`) 재기준 | #3947 sql 3건, #4647 shell `_02_having` | 통과 |

- 변경된 case는 모두 답안이 있고, 헤더 주석에 `;` 없음. 본문의 "develop에서 trace 줄만 달라 NOK" 주장은 CI 증거와 모순 없음.
- 판정: 두 TC PR 승인 가능.

## Runtime Verification

- CI: gha-ci run 41016954991, head `e33868668` debug(optdebug)/release 빌드 pass. sql(17693)/medium(975)/shell(3530) 모두 pass, `tc_branch=tc/pr-8335` (sql·medium `389c328ab`, shell `17ac99296`). `cbrd_27468.sql`, `_01_with_rollup`, `bug_bts_13764`, `cbrd_27177` ok.
- 로컬 smoke(SA 모드, 직렬): CI optdebug tarball head `e33868668` (libcubrid sha256 `07f383b3`) vs merge-base `cd341a6d6` (`47e5ab3a`). 10만 행 테이블에서 LIMIT, ORDER BY LIMIT, `use_desc_idx` + DESC ROLLUP, HAVING, NULL 키, 인라인 뷰 LIMIT 9개 질의와 ORDER BY 3개 질의: 결과 행 diff 0줄, 차이는 플랜·시간 줄뿐. `use_desc_idx` 힌트가 있어도 ROLLUP은 `Sort(group by)`로 남음(역방향 skip 없음, PR 설명과 일치). 티켓 재현 질의 105행 일치.
- 병렬 skip 경로는 로컬에서 돌리지 않았다(SA 모드). 병렬 증거는 CI TC의 trace `parallel workers` 줄.
