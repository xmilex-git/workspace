# PR #8354 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8354](https://github.com/CUBRID/cubrid/pull/8354)
**제목:** [CBRD-27728] Allow parallel index scan for GROUP BY skip plans whose first GROUP BY column is DESC
**작성자:** shparkcubrid
**HEAD SHA:** `dbbf8abca` (develop merge-base `309265e6d`, 이후 develop의 `src/query/parallel`, `query_executor.c` 변경 없음)
**JIRA:** CBRD-27728 (Improve Function/Performance, Develop) / 연관: CBRD-27869 (검증 중 발견한 별개 결함, 이 PR 범위 밖), CBRD-27468
**TC PR:** CUBRID/cubrid-testcases#3970 (`tc/pr-8354` `d81914abe`) / cubrid-testcases-private-ex#4680 (draft, 변경 없음)
**리뷰 일시:** 2026-11-02
**리뷰 결정:** 엔진 PR #8354 Approve (top-level 측정 요약) / TC PR #3970 Approve (코멘트 없음) / private-ex #4680 리뷰 없음 (변경 없음)

> **TL;DR** (Non-blocking): `groupby_skip && groupby_desc` 병렬 금지 조건 하나를 빼는 변경이고, 병렬 GROUP BY skip 병합(`qexec_gby_skip_key_cmp`)이 스캔 방향과 무관하게 맞다는 근거가 코드와 실행 모두에서 확인된다. release 1M 행 A/B에서 대상 질의 2개가 861 -> 190 ms, 594 -> 191 ms로 빨라졌고 결과는 행 순서까지 같다.

## Summary

- **변경 요약**: 첫 GROUP BY 컬럼이 DESC인 GROUP BY skip 플랜도 병렬 index scan 허용. ORDER BY skip은 직렬 유지
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음 (참고: DESC 인덱스 정방향 경우는 총 instructions가 21% 늘어남, Runtime Verification 참조)

---

## Findings

없음

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC 1: 재현 질의가 병렬 index scan, 병렬 해시 수준 속도 | A/B: Q2 861 -> 190 ms (해시 177-218 ms), trace `parallel workers: 4` | 충족 |
| AC 2: ASC/DESC/섞인 인덱스 x GROUP BY 방향, KEYLIST/RANGELIST, NULL, non-covering 결과 = 직렬 | TC Case 1-6 (`no_parallel_scan` 쌍둥이), PR 본문 128건, A/B Q1-Q4 vs H1-H4 차이 0줄 | 충족 |
| Implementation: `groupby_desc` 조건 제거, ORDER BY skip 직렬 유지 | `px_scan_checker.cpp` 조건 `orderby_skip`만 남김, TC Case 7 | 충족 |
| Implementation: `is_groupby_skip_parallel` 주석 정리 | 반영 | 충족 |

design.md / test.md 첨부 없음 (JIRA 본문이 Implementation, AC를 담음). CBRD-27869(NULL 하한 BETWEEN OR 범위 유실)는 develop, 11.4.6에서도 나는 별개 결함이고 이 PR이 새 경로를 만들지 않는다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| ASC 인덱스 역순, GROUP BY DESC (커버링/비커버링) | #3970 Case 1, 2 | 통과 |
| DESC 인덱스 정순 GROUP BY DESC, 역순 GROUP BY ASC | #3970 Case 3 | 통과 |
| 섞인 방향 인덱스 `(a, b DESC)` | #3970 Case 4 | 통과 |
| KEYLIST(IN) / RANGELIST(OR BETWEEN) | #3970 Case 5 | 통과 |
| NULL 그룹 키 (DESC에서 NULL이 마지막) | #3970 Case 6 | 통과 |
| ORDER BY skip DESC는 직렬 | #3970 Case 7 | 통과 |
| 파티션, `index_scan_in_oid_order=yes`, 동시 DML | PR 본문 로컬 검증만, TC 없음 | 통과 (본문) |

- 모든 변경 case에 answer 있음, 헤더 주석에 `;` 없음. `cbrd_27664` Case 12, `cbrd_27689` Q6은 DESC skip이 병렬로 바뀌어 trace 1줄씩 추가.
- `tc/pr-8354`에 develop의 `cbrd_27397` answer 수정(cafde972c)이 cherry-pick되어 있음. develop과 내용이 같아 merge 시 차이 없음.
- `set trace off` 위치 지적(greptile)은 이미 달린 코멘트라 제외.
- private-ex #4680은 변경 없는 draft -> 닫으면 됨.

## Runtime Verification

- **CI**: gha-ci run 41388320567 (engine `dbbf8abca`, TC `f98841aee`): medium 975, shell 3534 통과, sql NOK 2건 = `cbrd_27689`(TC 미반영, 이후 `d81914abe`에서 수정), `cbrd_27397`(develop TC 결함, cherry-pick). 재실행 41396375376 (TC `d81914abe`) sql 233건 통과.
- **fail-before** (optdebug CI 빌드 `309265e6d`, libcubrid `19120405`, TC `d81914abe`, `just ctp sql`): `cbrd_27728` NOK 9줄, `cbrd_27664` 1줄, `cbrd_27689` 1줄. 차이는 모두 `parallel workers` trace 줄, 결과 행 차이 0, core 0. pass-after는 CI.
- **성능 A/B** (release CI 빌드 base `309265e6d` libcubrid `8adf8e8d` / head `dbbf8abca` libcubrid `a9349a61`, 기본 conf parallelism=4, 1M 행 78그룹, 7회 교차 중앙값, loadavg 12-14):

| 질의 (인덱스, 읽기 방향, GROUP BY) | base ms | head ms | 총 instructions:u (M) | 최대 스레드 (M) |
|---|---|---|---|---|
| Q1 ASC 인덱스 정방향 ASC | 187 병렬 | 184 병렬 | 5301 -> 5301 | 1354 -> 1332 |
| Q2 ASC 인덱스 역방향 DESC | 861 직렬 | 190 병렬 | 6321 -> 5202 (0.82) | 6317 -> 1338 (0.21) |
| Q3 DESC 인덱스 정방향 DESC | 594 직렬 | 191 병렬 | 4377 -> 5301 (1.21) | 4374 -> 1345 (0.31) |
| Q4 DESC 인덱스 역방향 ASC | 184 병렬 | 187 병렬 | 5201 -> 5201 | 1326 -> 1306 |
| H1-H4 `USING INDEX NONE` (병렬 해시) | 177-195 | 179-218 | 동일 (1.00) | 동일 |

  순서를 바꾼 2차 패스도 Q2 0.226, Q3 0.322로 같음. H행의 0.93-1.23 흔들림은 2차 패스에서 재현 안 됨(잡음, instructions 동일). 결과는 base/head, Q/H 모두 행 순서까지 차이 0줄.
- Q3는 직렬 정방향 skip(4.4G)이 병렬 경로(5.3G, Q1과 같음)보다 일이 적다. 빈 서버에서는 3.1배 빠르고, 모든 코어가 바쁜 서버에서는 CPU를 21% 더 쓴다. 병렬 GROUP BY skip(CBRD-27664) 경로 자체의 비용이라 이 PR의 결함은 아님.
