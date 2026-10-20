# PR #8206 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8206](https://github.com/CUBRID/cubrid/pull/8206)
**제목:** [CBRD-27689] Allow parallel index scan when the first ORDER BY column is DESC but the order is not skipped
**작성자:** shparkcubrid
**HEAD SHA:** `8cbdf888a` (develop merge-base `cc947788d`)
**JIRA:** CBRD-27689 (Improve Function/Performance, Confirmed) / 연관: RND-2589 (분석 배경, 같은 결함 아님)
**TC PR:** CUBRID/cubrid-testcases#3800 (`tc/pr-8206` `445163301`) / cubrid-testcases-private-ex#4481 (빈 draft, 파일 변경 없음)
**리뷰 일시:** 2026-10-20
**리뷰 결정:** 엔진 PR #8206 Approve / TC PR #3800 Approve (Q5/Q6 suggestion 인라인 2건) / private-ex #4481 리뷰 없음

> **TL;DR** (Non-blocking): 엔진 변경은 맞다. desc 플래그를 읽는 곳은 `scan_get_index_oidset` 한 곳이고 거기서도 skip일 때만 쓰므로, checker에서 desc 조건을 빼도 skip 직렬은 그대로다. TC의 Q5/Q6는 범위가 좁아 옵티마이저 선택도 게이트에서 이미 직렬이 되므로, 정렬 생략 게이트가 사라져도 통과한다.

## Summary

- **변경 요약**: `px_scan_checker.cpp` 인덱스 스캔 병렬 금지 조건에서 `orderby_desc` / `groupby_desc` 제거
- **주요 이슈**: TC Q5/Q6가 "정렬 생략이면 직렬" 판정을 검증하지 못함 (`PARALLEL(4)` 힌트로 해결)
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)

1. TC `cbrd_27689.sql` Q5/Q6 — `name > 'Char049995'` / `> 'Char049998'` 범위는 선택도 x 인덱스 페이지가 `parallel_index_scan_page_threshold` 미만이라 `qo_apply_parallel_index_scan_threshold` (옵티마이저가 인덱스 스캔 병렬 차수를 정하는 함수, `metric < threshold` -> `PT_SPEC_FLAG_NO_PARALLEL_SCAN`)에서 이미 직렬이 된다 -> checker의 `orderby_skip || groupby_skip` 조건이 지워져도 Q5/Q6 답은 그대로라 JIRA 인수 기준 2를 지키지 못한다.
   - 근거(smoke, PR head): 같은 좁은 범위에 정렬 생략이 아닌 `order by v desc, name`(A2)도 직렬. 여기에 `/*+ PARALLEL(4) */`(A3)를 붙이면 `parallel workers: 4`.
   - 수정: Q5/Q6를 `/*+ recompile PARALLEL(4) */`로 바꾼다. 힌트는 선택도 게이트를 건너뛴다(`has_hint` 분기). PR head에서 A4/A5(Q5/Q6 + 힌트)는 직렬, `skip order by: true` / `group by nosort: true`, 내림차순 결과 그대로.

### Notes (게시하지 않음)

- MRO (`IN` 다중 범위 + `ORDER BY ... LIMIT`의 인덱스 상위 N 최적화): 첫 정렬 컬럼이 DESC인 MRO도 병렬 대상이 되어 PR 본문 측정으로 직렬 1.3ms -> 병렬 56ms. 작성자가 PR 본문에 밝히고 ASC와 맞추는 것으로 결정했으므로 다시 묻지 않는다. smoke M2(`PARALLEL(4)`, `parallel workers: 4, mro: true`) 결과 = M3(`NO_PARALLEL_SCAN`).
- #8207 (CBRD-27664)이 같은 checker 조건 줄을 고친다. 나중 PR의 sync에서 `orderby_skip || (groupby_desc && groupby_skip)` + `is_groupby_skip_parallel` 형태로 풀어야 #8206 Q4와 #8207 Case 12가 함께 맞는다. #8207 sync 때 처리.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 인수 1: 정렬 생략이 아닌 DESC 질의는 병렬 | CI `cbrd_27689` ok, smoke head Q1/Q3/Q4 병렬 (develop 직렬) | 충족 |
| 인수 2: 정렬 생략(역방향 포함)은 직렬, 순서 동일 | skip 조건 유지. smoke A4/A5/A6(힌트 포함) 직렬, 순서 동일 | 충족 |
| 인수 3: 결과 동일 | smoke TC/probe 결과 행 head = develop, CI sql 전체 pass | 충족 |
| 구현: desc를 skip과 AND로 묶음 | desc 항 제거. `skip || (desc && skip)` = `skip` 이라 동치 | 충족 |
| DoD: 신규 TC (조합별 병렬 여부와 결과) | `cbrd_27689` 추가, Q5/Q6 판별력 없음 | 부분 (Finding 1) |
| DoD: 영향받는 기존 TC 답지 갱신 | `tc/pr-8206`로 sql 17593건 pass, 갱신 대상 없음 | 충족 |

## TC PRs

JIRA `test.md` 첨부가 없으므로 시나리오는 엔진 PR 측정 표 6행이다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| `GROUP BY SUBSTR ORDER BY c DESC` 병렬 | #3800 Q1 (+ `NO_PARALLEL_SCAN` 결과 비교) | 통과 |
| 같은 질의 `ORDER BY c ASC` 대조 | #3800 Q2 | 통과 |
| `ORDER BY p DESC` (그룹 키, 정렬 생략 아님) 병렬 | #3800 Q3 | 통과 |
| `GROUP BY MOD(v,3) DESC` 병렬 | #3800 Q4 | 통과 |
| `ORDER BY name DESC` 정렬 생략 직렬 | #3800 Q5, 선택도 게이트로 직렬 | 부분 (Finding 1) |
| `GROUP BY name DESC` 정렬 생략 직렬 | #3800 Q6, 선택도 게이트로 직렬 | 부분 (Finding 1) |

- #3800: case와 answer 짝 맞음, 헤더 주석에 `;` 없음. 본문 "수정 빌드 OK, develop NOK(Q1/Q3/Q4 trace에 parallel workers 없음)"는 smoke와 일치.
- private-ex #4481: 초기화 커밋과 develop merge만 있고 파일 변경 없음. 별도 리뷰 불필요(TC Merge Gate 기준으로 닫을 대상).
- 판정: 부분. Q5/Q6에 `PARALLEL(4)`를 넣으면 충족.

## Runtime Verification

- CI gha-ci run 39391105360: 엔진 `8cbdf888a` optdebug, TC `tc/pr-8206` (public `445163301`, private `742446237`). sql 17593 / medium 975 / shell 3469 모두 pass. `sql/_36_guava/cbrd_27689` ok (shard 09, 6718ms).
- smoke (lead, C/S `csql -C`, 격리 namespace, `data_buffer_size=512M`, CI 설치본 그대로):
  - 빌드: head `8cbdf888a` optdebug (`libcubrid.so` sha256 `07aaf603...`), develop merge-base `cc947788d` optdebug (`0fc14e9a...`).
  - TC SQL(`445163301`): develop은 Q2만 병렬, Q1/Q3/Q4 직렬. head는 Q1-Q4 병렬. Q5/Q6는 둘 다 직렬. 결과 행 동일.
  - probe(`evidence/p1.sql`): A2 직렬 / A3 병렬(head), A4-A6 직렬 + 순서 동일, M2 병렬 + 결과 = M3(head). develop은 A3, M2 직렬. 결과 행 head = develop.
- 새 CTP 실행 없음: CI가 head + `tc/pr-8206`로 전 suite를 돌렸다. Finding 1의 수정안(힌트)은 csql smoke로만 확인했고 CTP 답지로는 돌리지 않았다.
- develop drift: merge-base 이후 develop 커밋은 #8158(CBRD-27548, 파티션 NL 조인) 하나로 이번 경로와 무관.

## Existing Comments

| 작성자 | 내용 | 상태 |
|---|---|---|
| greptile (#3800 요약) | Q1/Q2 집계값이 모두 3000이라 DESC/ASC 결과가 같음, 데이터 보강 권장 | 답변 없음 |
