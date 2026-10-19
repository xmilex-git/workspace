# PR #7834 코드 리뷰 보고서 (3차)

**PR:** [CUBRID/cubrid#7834](https://github.com/CUBRID/cubrid/pull/7834)
**제목:** [CBRD-27329] Refactor serial CONNECT BY: hash child-finding and in-memory DFS execution
**작성자:** HyunukLee
**HEAD SHA:** `31f2185135a1d799f5526ead2d0d565ad780d50f` (develop merge-base `30043f492`, 2차 리뷰 `2682c67a8` 이후 커밋 6개)
**JIRA:** CBRD-27329 (Improve Function/Performance, Open, 10-01 이후 변경 없음) / 연관: CBRD-27328 (Blocks, 같은 결함 아님)
**TC PR:** CUBRID/cubrid-testcases#3520 (`tc/pr-7834` `85671e9cf`, 09-18 이후 변경 없음) / cubrid-testcases-private-ex#4178 (빈 draft)
**리뷰 일시:** 2026-10-08 (1차 10-01, 2차 10-07)
**리뷰 결정:** 엔진 PR Request changes (스레드 답글 2건 + 새 리뷰 NIT 1건, 고쳐진 스레드 3개 resolve) / TC PR #3520 새 리뷰 없음 (10-07 Request changes 유지) / #4178 리뷰 없음 (빈 draft)

> **TL;DR** (Blocking): 2차 인라인 지적 6건 중 4건(생성기 fast-path, OSB 동순위 2000건, 사이클 필터 O(1), 정렬 실패 정리)은 고쳐졌고 실행으로 확인했습니다. 남은 Blocking은 둘입니다. PK만 있는 테이블의 루트 순서는 작성자가 후속 작업으로 남겼습니다. 스필 메모리 증폭은 star에서는 풀렸지만, 상한 0의 깊은 체인에서 여전히 경로 노드마다 64KB 버퍼를 잡아 체인 5만에서 3.8GB입니다. 새로 찾은 것은 형제 10만 건 동순위 ORDER SIBLINGS BY가 상한 설정에 따라 순서가 달라지는 문제입니다.

## Summary

- **변경 요약**: 2차 이후 6개 커밋. 생성기 fast-path에서 `TYPE_SP`, `:=`, `INCR`/`DECR` 제외, 청크 크기 하한(membuf), 비해시 스필 OSB 정렬 방향 분기, 경로 해시 버킷 인덱스, 정렬 실패 시 입력 리스트 파기.
- **주요 이슈**: 루트 순서 미수정. 상한 0 체인의 경로 스필 메모리. 큰 동순위 형제 집합의 OSB 순서가 설정에 따라 다름.
- **확인 필요 사항**: PR 본문 게이트 설명 갱신(2차 상단 코멘트, 미응답).

---

## Findings

### Blocking (must fix)

- **[2차 이월] PK만 있는 테이블에서 START WITH 루트 순서가 바뀜** (`src/optimizer/rewriter/query_rewrite_select.c:4134`)
  - 상태: 작성자가 "START WITH 루트 스캔은 인덱스를 유지하고 자식 탐색만 해시로" 고치겠다고 답했고, head에는 아직 없습니다.
  - 재확인(optdebug SA): `foo (a PK, b)`에 `START WITH a < 4 CONNECT BY PRIOR a = b`를 실행했습니다. develop은 `(1,2) (2,3) (1,2) (3,4) (2,3) (1,2)` 순서이고, head는 `(3,4) (2,3) (1,2) (2,3) (1,2) (1,2)` 순서입니다.

- **[2차 일부 해결] 상한 0에서 깊은 체인의 경로 스필이 노드마다 64KB 버퍼를 잡음** (`src/query/query_executor.c:20445`)
  - 결함: `4ec087b4a`의 하한(`chunk_bytes = MAX (limit / 4, membuf_bytes)`)은 청크 크기의 상한만 늘립니다. 청크 개수는 줄이지 못합니다.
  - 원인: `qexec_connect_by_spill_if_needed`는 호출될 때마다 상주 중인 구간 `[path_scan_from, path_top)`만 청크로 씁니다. 상한 0에서는 그 구간이 직전 노드 하나뿐입니다. 그래서 경로 노드 하나가 temp 파일 하나가 되고, 그 파일마다 `temp_mem_buffer_pages`(4 x 16KB) membuf(temp 파일마다 미리 잡는 메모리 버퍼)가 붙습니다.
  - 결과: star(자식 스필이 `qexec_connect_by_spill_children_to_stack`에서 청크로 모아 씀)는 해결됐습니다. 체인은 깊이에 비례해 레벨당 약 60KB가 남습니다. 상한을 0으로 두면 OOM 위험이 그대로입니다.
  - 측정(release SA, ru_maxrss MB):

| 질의 | 128M | 8M(기본) | 1M | 64K | 0 |
|---|---|---|---|---|---|
| star 10만(해시), 2차 `2682c67a8` | 566 | 575 | 554 | 869 | 6843 |
| star 10만(해시), head | 512 | 506 | 498 | 488 | 487 |
| 체인 5만, 2차 | 463 | 833 | - | - | 3592 |
| 체인 5만, head | 790 | 806 | - | 805 | 3787 |

  상한 0이 아닌 칸은 SA 기본 RSS(약 500~800MB) 수준입니다. 같은 설정에서도 300MB 정도 흔들립니다.

### Non-blocking (should consider)

- **형제가 많으면 ORDER SIBLINGS BY 동순위 순서가 상한에 따라 달라짐** (`src/query/query_executor.c:20711`)
  - 원인: 인메모리 경로(`qexec_connect_by_sort_siblings`)는 안정 merge sort라서 동순위를 입력 순서로 둡니다. 스필 경로(`qexec_connect_by_spill_children_order`)는 `qfile_sort_list_with_func`(외부 정렬)를 씁니다. 외부 정렬은 입력이 크면 동순위의 입력 순서를 지키지 않습니다.
  - 증거(release, star 10만, `ORDER SIBLINGS BY k`, k = MOD(x, 7)):
    - 인덱스 경로: develop, head 64K, head 0의 출력은 같습니다(md5 `56c193c6`). 이 셋에서는 k=1 그룹이 id 86488부터 시작합니다. head 128M과 기본값의 출력(md5 `eb6caf43`)에서는 k=1 그룹이 입력 순서대로 id 3부터 시작합니다.
    - 해시 경로: head 128M/기본값(`567250bc`)과 head 0(`8f1b42e9`)이 다릅니다. 0에서는 k=1 그룹이 57221부터 시작합니다.
    - 형제 2000건(p3 9개 질의)에서는 develop과 모든 설정이 같습니다. 작성자의 8000건 검증도 이 범위 안입니다.
  - 결과: 같은 질의의 출력 순서가 `max_connect_by_dfs_size`에 따라 달라집니다. 상한 128M과 기본값은 develop과도 다릅니다. 행 집합은 같습니다. PR 본문은 "128M / 8M / 1M / 0 전 설정 bit-identical"이라고 적고 있습니다.
- `src/query/query_executor.c:20768`, `:673`: 하한이 생긴 뒤로 두 주석이 틀립니다. "a tiny limit keeps chunks tiny"와 "one reload re-admits at most a quarter"가 그렇습니다. 지금은 상한이 256KB보다 작아도 청크가 64KB입니다.

### Questions for the author

- 없음 (PR 본문 갱신 요청은 상단 코멘트로 다시 남김)

## JIRA -> Engine PR

JIRA에는 `design.md`/`test.md`가 없습니다. 그래서 본문의 Specification, Implementation, Acceptance Criteria를 기준으로 봤습니다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 사양: 사용자 가시 결과 불변 | 생성기 fast-path 수정됨, 루트 순서 미수정, 큰 동순위 OSB 순서가 develop과 다름 | 부분 (Blocking 1, Non-blocking 1) |
| 사양: `max_connect_by_dfs_size`가 DFS 튜플 메모리 상한 | star 해결, 상한 0 체인 3.8GB | 부분 (Blocking 2) |
| 구현 1: 인덱스 없는 단일 테이블 해시 리다이렉트 | 게이트가 "자식 컬럼 선두 인덱스"로 바뀌었고 본문은 옛 기준, 루트 순서 변경 | 부분 (Blocking 1) |
| 구현 2: 인메모리 해시 DFS, 사이클 해시 필터 | 경로 해시 버킷 인덱스 추가, 체인 25k~200k 선형, 사이클 배터리 develop과 같음 | 충족 |
| 구현 3: index-string 수도컬럼 제거 | 변경 없음 | 충족 |
| 구현 4: LEVEL 생성기 fast-path | 세션 변수, 저장 함수 develop과 같음(4행). 시리얼, 서브쿼리는 CONNECT BY에서 develop도 거부 | 충족 |
| 구현 5: DFS 상태 스필 | OSB 2000건 해결, 체인 메모리와 큰 동순위 순서 남음 | 부분 (Blocking 2, Non-blocking 1) |
| AC: 상한 128M/8M/1M/0 결과 상호 동일 | 형제 10만 동순위 OSB에서 다름 | 부분 (Non-blocking 1) |
| AC: CTP sql 회귀 없음 | NOK 55건이 2차와 같음. CONNECT BY 7건은 TC 답안 미갱신 | 미충족 (TC 갱신 필요) |
| DoD: 비인덱스 O(N^2) 자식 탐색 제거 | star 10만 0.25~0.29 s | 충족 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 인덱스/비인덱스/USE_DESC_IDX plan 표기 변경 | #3520 답안 9개, head 기준 7개와 `_52` hunk 미갱신(2차와 같음) | 미통과 |
| 스필 설정별 결과 동일, 스필 중 killtran 후 temp 회수 | 두 TC PR 모두 언급 없음 | 미통과 |
| 사이클 배터리, OSB 배터리, NO_HASH_LIST_SCAN A/B | 언급 없음 | 미통과 |
| 생성기 fast-path(세션 변수, 저장 함수 포함) | 언급 없음 | 미통과 |
| 리뷰에서 고친 결함 회귀 케이스 | 언급 없음 | 미통과 |

- #3520은 2차 Request changes 뒤로 커밋도 답글도 없습니다. 2차 판정(Request changes)이 그대로 유효합니다.
- #4178은 빈 draft입니다.

## Runtime Verification

- **GitHub CI**: head에서 gha-ci `/run`은 아직 실행되지 않았습니다. Check TC PRs는 실패, code-style/cppcheck/license는 통과입니다.
- **빌드**: head `31f218513` optdebug와 release는 로컬 증분 빌드입니다(libcubrid.so md5 변경 확인, conf는 base와 같은 `d6b0624d`). base는 2차와 같습니다(optdebug: gha-ci tarball, release: 로컬 빌드).
- **CTP**: head optdebug, `just ctp sql+medium`, testcases `tc/pr-7834` `85671e9cf`.
  - sql은 17456건 중 NOK 55건입니다. 2차 head 실패 목록과 같고, diff 본문 55건도 모두 같습니다.
  - medium은 975/975 통과, core 0입니다.
- **probe** (optdebug SA/CS, base와 head 비교):
  - 세션 변수 생성기와 저장 함수 생성기 2종(시리얼, 호출 횟수)은 두 빌드 모두 4행입니다.
  - 사이클 배터리 5개 질의는 같습니다.
  - p3 OSB 9개 질의는 head 기본값, 65536, 0에서 모두 develop과 같습니다.
  - 루트 순서는 다릅니다(Blocking 1).
- **실측** (release SA, 1회 워밍업 뒤 3회 중앙값):
  - 호스트 부하가 load 60에서 24 사이여서 시간은 참고용입니다. RSS는 부하와 무관합니다.
  - 체인 25k/50k/100k/200k는 0.32/0.39/0.53/0.80 s입니다(2차 0.54/1.25/4.20/15.3 s).
  - star 상한 0은 1.56 s입니다(2차 1.29 s, 부하 영향 가능).
- **증거 위치**: `.git_ignored_dir/scratch/pr7834/evidence/rr1008/` (`perf-report.txt`, `probes-report.txt`, `ctp-report.txt`, `order/`), `evidence/perfrun3/`.

## Existing Comments

작성자는 10/08 05:42에 2차 인라인 6건에 모두 답했습니다. 그중 루트 순서는 "이어서 작업"으로 남았습니다. 그 밖에 답이 없는 top-level 코멘트는 없습니다.
