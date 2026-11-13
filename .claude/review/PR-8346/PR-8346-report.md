# PR #8346 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8346](https://github.com/CUBRID/cubrid/pull/8346)
**제목:** [CBRD-27685] Use GROUP BY skip on join plans and stop the join scan at the GROUP BY LIMIT
**작성자:** shparkcubrid
**HEAD SHA:** `080aff3cd` (develop merge-base `582fa3941`)
**JIRA:** CBRD-27685 (Improve Function/Performance, Develop) / 연관: CBRD-27664(#8207, 단일 테이블 GROUP BY skip), CBRD-27728(LIMIT 없는 조인, 후속), CBRD-27864(LIMIT NL 바깥 스캔 비용, 후속)
**TC PR:** CUBRID/cubrid-testcases#3961 (`tc/pr-8346` `35904792c`) / CUBRID/cubrid-testcases-private-ex#4672 (`tc/pr-8346` `33317ed91`)
**리뷰 일시:** 2026-11-02
**리뷰 결정:** 엔진 PR Approve (NIT 1건 inline), TC #3961 Approve, TC #4672 Approve

> **TL;DR** (Non-blocking): 머지를 막을 결함은 찾지 못했습니다. head optdebug CI(sql/medium/shell 모두 pass)와 CI에 없는 조인 형태 11개 smoke에서 skip 플랜 결과가 USE_HASH 결과와 같았습니다. 남은 것은 정적 프로토타입 위치 하나입니다.

## Summary

- **변경 요약**: `GROUP BY <바깥 키> LIMIT n` 조인에서 NL 체인 맨 바깥 인덱스 스캔 순서로 GROUP BY 정렬을 건너뛰고(GROUP BY skip), 그룹 한도에 닿으면 조인 전체를 멈춤
- **주요 이슈**: 없음 (프로토타입 위치 NIT 1건)
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)

1. `src/optimizer/query_planner.c:438-445` — 새 static 프로토타입 8개가 `qo_plan_is_orderby_skip_candidate`(정의 16479행)와 `qo_is_sort_limit`(16588행) 사이에 들어가 정의 순서와 어긋남. 정의는 `qo_check_groupby_iscan` 1198행, `qo_groupby_limit_groups`..`qo_plan_is_groupby_limit_join` 4475-4662행, `qo_plan_drives_groupby_skip_only`/`qo_find_groupby_skip_outer_on_info` 7973-7994행. 기존 블록의 이웃 둘(16479 -> 16588)은 정의 순서였으므로 이 PR이 순서를 깸.

## JIRA -> Engine PR

JIRA에는 `design.md`/`test.md` 첨부가 없어 본문의 Acceptance Criteria와 Implementation을 기준으로 봤습니다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC 성능: 시나리오 32가 정렬 없는 그룹 키 순서 조인, trace rows가 앞쪽 일부, 변경 전보다 빠름 | PR 본문 측정: 684 -> 17 ms, title 273행 / aka_title 126행, instructions 9.35e9 -> 0.139e9 | 충족 |
| AC 결과: HAVING, LIMIT offset, `GROUP BY g ORDER BY g LIMIT n`, GROUP_CONCAT·DISTINCT, 안쪽 매칭 없는 키 | TC 케이스 1-6이 USE_HASH 결과와 비교, `HAVING groupby_num()` 형태는 shell `cbrd_26354` 11·12, HAVING 집계는 develop 플랜 유지(케이스 7) | 충족 |
| AC 회귀 없음: 50개 시나리오 결과 행 수 동일, 플랜이 바뀐 시나리오가 느려지지 않음 | PR 본문: 행 수 모두 같음, 플랜 변경은 32번뿐 | 충족 |
| Impl 옵티마이저: 그룹 키 순서 인덱스 스캔을 조인 바깥 후보로 유지, LIMIT n 그룹만 읽는 NL 비용 | `qo_check_plan_on_info`, `qo_check_planvec`, `qo_find_groupby_skip_outer_on_info`, `qo_nljoin_cost` | 충족 |
| Impl 실행기: 스캔 중 집계를 조인에서 쓰고, 그룹 한도에서 조인 전체 중단 | `qexec_intprt_fnc` scan_ptr 루프의 `gby_skip_state->stopped` 확인, 케이스 2(0으로 나누기 행 미도달) | 충족 |
| Spec: GROUP BY skip을 쓰지 않던 조건(ROLLUP, CONNECT BY, ROWNUM, prefix 인덱스) 유지 | `qo_groupby_limit_groups`, `qo_plan_is_groupby_skip_candidate`가 같은 조건으로 거름 | 충족 |

연관 이슈 중 같은 결함을 다루는 것은 없습니다. CBRD-27728, CBRD-27864는 이 PR이 남긴 후속입니다.

## TC PRs

시나리오는 PR 측정표의 행입니다(JIRA `test.md` 없음).

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 시나리오 32 (GROUP_CONCAT, LIMIT) | #3961 케이스 1 | 충족 |
| COUNT, LIMIT 여러 크기 | #3961 케이스 2, 4 (LIMIT offset, 그룹 수보다 큰 LIMIT) | 충족 |
| LIMIT 100000 -> develop 해시 조인 | 비용 경계, 100만 건 데이터 의존 -> TC 대상 아님 | 해당 없음 |
| LEFT JOIN / `GROUP BY id ORDER BY id LIMIT` | #3961 케이스 3, 4 | 충족 |
| LIMIT 없음 / HAVING 집계 -> develop 플랜 | #3961 케이스 7 | 충족 |
| 안쪽 파티션·상속 계층 -> 정렬 플랜 (Greptile 지적) | #3961 케이스 8 | 충족 |
| 기존 셸 TC 플랜 변경 | #4672 `cbrd_26354` 11·12 답지 갱신 | 충족 |

- #3961: 케이스 1개, 답지 1개. 헤더 주석에 `;` 없음(`;`는 `evaluate` 문자열 안에만 있고 CI가 OK). 본문의 release/debug OK, develop NOK 주장은 CI와 맞음.
- #4672: 답지 2개만 바뀜. 플랜이 `temp(group by)` -> `idx-join` + `skip GROUP BY`, card 99961 -> 1001.
- 판정: 두 TC PR 모두 승인 가능.

## Runtime Verification

| 출처 | 빌드 | 테스트케이스 ref | 결과 |
|---|---|---|---|
| gha-ci run 41373690721 | `080aff3cd` debug(optdebug) | `tc/pr-8346` sql/medium `35904792c`, shell `33317ed91` | sql 17697 / medium 975 / shell 3530 모두 pass, `cbrd_27685` ok |
| 리뷰 smoke (SA, `csql -S`) | 같은 CI tarball, `libcubrid.so` sha256 `1ccb99f9...` | TC 스키마 재사용, 질의 11개 | skip 플랜 7개(RIGHT JOIN, 파생 테이블 안쪽, self join, 범위 조인 조건, CTE 안쪽, 3개 테이블 비고유 그룹 키, EXISTS) 모두 USE_HASH 결과와 차이 0줄. 3개(GROUP BY에 안쪽 컬럼, SELECT 상관 서브쿼리, 비인덱스 그룹 키)는 해시+정렬 플랜이고 결과 같음. `HAVING groupby_num()` + LIMIT 1개는 파서가 거부(PR이 건드리지 않는 규칙) |

- fail-before(develop NOK)는 작성자 결과를 인용했고, 다시 돌리지 않았습니다.
- develop drift: merge-base 이후 #8196이 `query_executor.c`를 크게 바꿨지만 텍스트 충돌은 없고, 새 배치 경로는 힙 스캔 전용이라 인덱스 바깥 스캔인 이 경로와 겹치지 않습니다. 병합 빌드는 돌리지 않았습니다.

## Existing Comments

Greptile P1(안쪽 파티션에서 집계 행 누락)은 작성자가 7b9391080으로 고치고 TC 케이스 8을 추가해 답했습니다. 남은 미답변 코멘트는 없습니다.
