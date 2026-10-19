# PR #7834 코드 리뷰 보고서 (4차)

**PR:** [CUBRID/cubrid#7834](https://github.com/CUBRID/cubrid/pull/7834)
**제목:** [CBRD-27329] Refactor serial CONNECT BY: hash child-finding and in-memory DFS execution
**작성자:** HyunukLee
**HEAD SHA:** `b77dfeaa97487d12316927315c559ed6cfb9df06` (develop merge-base `276f7e94c`, 3차 `31f218513` 이후 PR 커밋 6개 + develop merge 2개)
**JIRA:** CBRD-27329 (Improve Function/Performance, Open, 10-01 이후 변경 없음) / 연관: CBRD-27328 (Blocks, 같은 결함 아님)
**TC PR:** CUBRID/cubrid-testcases#3520 (`tc/pr-7834` `640156836`, 10-13 develop merge만 추가) / cubrid-testcases-private-ex#4178 (`fb010c31e`, 변경 파일 0)
**리뷰 일시:** 2026-10-13 (1차 10-01, 2차 10-07, 3차 10-08)
**리뷰 결정:** 엔진 PR Approve (review 5497957135, 스레드 답글 4건, 3개 resolve, 루트 순서 스레드는 열어 둠) / TC PR #3520 Approve (5497957235) / #4178 Approve (5497957365) - 사용자 지시로 세 레포 모두 approve

> **TL;DR** (Non-blocking): 3차의 상한 0 체인 스필 메모리는 고쳐졌습니다(체인 5만 피크 RSS가 상한 0에서 3787MB, 지금은 모든 상한에서 462~466MB). 다른 리뷰어가 지적한 생성기 fast-path 누락도 고쳐졌습니다. 루트 순서는 SQL이 정하지 않는 순서라 작성자 선택지 2(유지)를 받아들이고 Blocking에서 내렸습니다. 대신 JIRA 사양 변경으로 기록해 달라고 요청합니다. 남은 것은 PR 본문과 JIRA 문구, TC 답안 갱신입니다.

## Summary

- **변경 요약**: 스필 상한을 membuf 4개(기본 256KB) 밑으로 내려가지 않게 했습니다. 생성기 fast-path의 제외 판정은 develop의 `domain_non_cacheable_operator()`를 재사용하고, 조건부와 값 목록까지 탐색합니다. 계층 질의에서 COUNT 인덱스 통계 최적화를 끄는 1줄 수정(`2fed14748`)도 추가됐습니다.
- **주요 이슈**: PR 본문/JIRA 문구가 코드와 다름. 루트/형제 순서 변화가 사양에 없음.
- **확인 필요 사항**: `2fed14748`이 고친 COUNT 결함은 develop에도 있음. PR 본문/JIRA 기록과 TC 추가 여부.

---

## Findings

### Non-blocking (should consider)

- **PR 본문과 JIRA 사양을 지금 코드에 맞춰야 함**
  - 게이트 기준: 문구는 "정상 인덱스가 하나도 없을 때만 리다이렉트"입니다. 코드는 `531b2583` 이후 자식 컬럼으로 시작하는 인덱스가 있을 때만 기존 플랜을 유지합니다. 3차 상단 코멘트에서 요청했는데 아직 답이 없습니다.
  - 상한 0의 의미: 문구는 "0이면 노드마다 스필"입니다. `45abfdbc8` 이후 `qexec_connect_by_spill_init`는 상한을 `MAX (param, membuf_bytes * CONNECT_BY_SPILL_CHUNKS_PER_LIMIT)`로 잡습니다. 그래서 `temp_file_memory_size_in_pages` 기본값에서는 256KB 미만 값이 모두 256KB로 동작합니다.
  - 설정 간 동일: 문구는 "128M / 8M / 1M / 0 전 설정 bit-identical"입니다. 하지만 형제가 많으면 동순위 형제의 순서가 상한에 따라 다릅니다(작성자 답글 10-12).
  - 출력 순서: JIRA 사양은 "사용자 가시 결과 불변"이라고 적고 있습니다. 실제로는 인덱스 경로가 해시 경로로 바뀌는 질의에서 ORDER SIBLINGS BY가 없으면 루트/형제 순서가 develop과 달라집니다(`bug_bts_9613`).
    - 이 순서는 SQL이 정하지 않습니다. 근거: Oracle "Without an order_by_clause, no guarantee exists...", Db2 "Siblings at the same level of recursion have no specific order", CUBRID 매뉴얼 `hq.rst`에는 기본 순서 보장 문구가 없음.
    - 부모 바로 뒤에 자식이 오는 계층 순서는 PR에서도 유지됩니다. 따라서 동작은 유지하되, 사양 변경으로 JIRA에 적어야 합니다.

## JIRA -> Engine PR

JIRA에는 `design.md`/`test.md`가 없습니다. 그래서 본문의 Specification, Implementation, Acceptance Criteria를 기준으로 봤습니다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 사양: 사용자 가시 결과 불변 | 행 집합과 계층 순서는 같음. 루트/형제 순서는 바뀜(SQL 미정의) | 부분 (Non-blocking 1, 사양 문구) |
| 사양: `max_connect_by_dfs_size`가 DFS 튜플 메모리 상한 | 체인 5만, star 10만 모두 상한과 무관하게 RSS 일정. 실효 하한 256KB가 사양에 없음 | 부분 (Non-blocking 1) |
| 구현 1: 인덱스 없는 단일 테이블 해시 리다이렉트 | 게이트 기준 문구가 옛 기준 | 부분 (Non-blocking 1) |
| 구현 2: 인메모리 해시 DFS, 사이클 해시 필터 | 3차와 같음. JSON 해시는 다른 리뷰어 스레드에서 진행 중 | 충족 (Existing Comments 참고) |
| 구현 3: index-string 수도컬럼 제거 | 변경 없음 | 충족 |
| 구현 4: LEVEL 생성기 fast-path | 비결정 항 probe 11개와 결정적 대조 2개가 develop과 같음. UUID, DRANDOM 조건이 develop처럼 작은 값으로 흔들림. 결정적 생성기는 여전히 fast-path(0.08 s, 비결정 0.59 s) | 충족 |
| 구현 5: DFS 상태 스필 | 체인 메모리 해결 | 충족 |
| AC: 상한 128M/8M/1M/0 결과 상호 동일 | 큰 동순위 OSB 순서만 다름(SQL 미정의) | 부분 (Non-blocking 1, 문구) |
| AC: CTP sql 회귀 없음 | gha-ci NOK 9건이 모두 답안 갱신 대상(아래 TC PRs) | 미충족 (TC 갱신 필요) |
| DoD: 비인덱스 O(N^2) 자식 탐색 제거 | 3차와 같음 | 충족 |
| (추가) `2fed14748` COUNT 인덱스 통계 최적화 제외 | develop에도 있는 결함을 고침. PR 본문/JIRA에 없음 | 확인 필요 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 인덱스/비인덱스/USE_DESC_IDX plan 표기 변경 | gha-ci sql NOK 8건이 답안 미갱신. `bug_bts_9613` 루트 순서 포함 | 미통과 |
| CONNECT BY 내부 정렬 제거로 trace 변경 | `_36_guava/cbrd_27510/16_hash_scan_build_keys` 답안의 `CONNECTBY` 아래 `ORDERBY` 줄 3곳 | 미통과 |
| 새 파라미터 노출 | private-ex shell `bug_bts_5423`에서 paramdump에 `max_connect_by_dfs_size` 2줄 추가 | 미통과 (#4178 변경 없음) |
| 스필 설정별 결과 동일, 스필 중 killtran 후 temp 회수 | 두 TC PR 모두 언급 없음 | 미통과 |
| 사이클 배터리, OSB 배터리, NO_HASH_LIST_SCAN A/B | 언급 없음 | 미통과 |
| 생성기 fast-path(세션 변수, 저장 함수, CASE 조건부 포함) | 언급 없음 | 미통과 |
| 리뷰에서 고친 결함 회귀 케이스(COUNT 포함) | 언급 없음 | 미통과 |

- #3520은 10-07 Request changes 뒤로 develop merge만 들어왔습니다. 10-07 판정이 그대로 유효합니다.
- 스필 TC를 쓸 때 주의할 점: 이제 `max_connect_by_dfs_size=0`만으로는 작은 데이터에서 스필이 일어나지 않습니다. DFS 상태가 256KB를 넘는 데이터를 써야 합니다.

## Runtime Verification

- **gha-ci** (head `b77dfeaa9`, run 38329955908, testcases `tc/pr-7834`):
  - build debug/release는 통과입니다.
  - sql은 17526건 중 NOK 9건입니다(TC `640156836`). 8건은 3차부터 알려진 CONNECT BY 답안 미갱신이고, 1건은 `cbrd_27510/16`의 trace 줄입니다. 데이터 행 diff는 없습니다.
  - medium은 통과입니다.
  - shell은 3296건 중 NOK 2건입니다(TC `fb010c31e`).
    - `bug_bts_5423`: paramdump에 새 파라미터가 나와서 생긴 diff이고, PR 때문입니다. 답안 갱신이 필요합니다.
    - `cbrd_27121-3`: 동시 delete/insert 뒤 heap 페이지 증가량이 81로 허용치 28을 넘었습니다. CONNECT BY를 쓰지 않는 케이스라 PR과 무관합니다. 최근 157회 run에서는 실패한 적이 없습니다.
- **로컬 빌드** (head `686745c39`, 새 worktree): optdebug와 release를 빌드했습니다(conf md5 `d6b0624d`). base는 develop `dbb986faf`의 gha-ci optdebug tarball입니다.
- **로컬 CTP** (`686745c39` optdebug, `just ctp sql+medium`, TC `85671e9cf`):
  - sql NOK는 73건입니다. 3차 55건이 그대로 있고, 새 18건은 base에서도 같은 diff로 실패합니다(TC 시점 차이).
  - medium은 975/975 통과, core는 0입니다.
- **probe** (optdebug SA):
  - 생성기 13개는 base와 같습니다.
  - 루트 순서는 다릅니다(PR `686745c39`과 `b77dfeaa9`가 서로 같음).
  - JSON 두 질의는 다릅니다(Existing Comments 참고).
  - COUNT: PK 테이블에서 START WITH 없는 `COUNT(*)`/`COUNT(id)`가 develop과 `686745c39`에서는 4(틀림), `b77dfeaa9`에서는 8(계층 행 수)입니다.
  - MIN/MAX는 base와 head 모두 계층 기준으로 맞습니다.
- **실측** (release SA `686745c39`, ru_maxrss MB, 3회 중앙값; 옆에서 CTP가 돌아 load 24~28이었으므로 시간은 참고용):

| 질의 | 128M | 8M(기본) | 64K | 0 |
|---|---|---|---|---|
| 체인 5만, 3차 `31f218513` | 790 | 806 | 805 | 3787 |
| 체인 5만, `686745c39` | 462 | 463 | 465 | 466 |
| star 10만(해시), `686745c39` | - | 505 | - | 487 |

- **범위 밖 관찰 (develop 결함, PR 무관)**:
  - `CONNECT BY ... AND CAST (c AS VARCHAR) LIKE CASE WHEN (@w := @w + 1) <= 3 THEN '1%' ELSE 'x' END`를 실행하면 base와 head 모두 `query_evaluator.c:481` `eval_assert_resolved_sides` assert로 abort합니다. core는 `/bench/ssd/core/core.csql.3321262.*`, `core.csql.3422300.*`입니다.
  - `COUNT(*) FROM tc_pk WHERE id > 0 START WITH id = 2 CONNECT BY ...`는 develop에서 1(틀림), PR에서 2입니다.
- **증거 위치**: `.git_ignored_dir/scratch/pr7834/rr4/evidence/` (`lane-*-report.txt`, `probes/`, `perf/`, `ci-*-failed.list`, `ctp-*`).

## Existing Comments

| 코멘트 | 내용 | 상태 |
|---|---|---|
| jihyekim-0 4245870661 (10-12) | JSON 사이클 해시: `"true"`/`true`, `-0.0`/`0.0`을 사이클로 못 잡음 | 작성자 답 없음. head에서 재현(develop 1행, head 2행) |
| HyunukLee 4253615626 (10-13) | 루트 순서 선택지 1(인덱스 스캔, 33% 느림)과 2(유지) 중 의견 요청 | 이번 리뷰에서 2로 답함 |
| xmilex-git 3차 상단 코멘트 (10-08) | PR 본문 게이트 기준 갱신, gha-ci 실행 | gha-ci는 실행됨. 본문은 미갱신 |
