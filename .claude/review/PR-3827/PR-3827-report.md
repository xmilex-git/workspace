# TC PR #3827 / #4515 리뷰 보고서 (CBRD-26678)

**PR:** [CUBRID/cubrid-testcases#3827](https://github.com/CUBRID/cubrid-testcases/pull/3827) (sql), [CUBRID/cubrid-testcases-private-ex#4515](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4515) (shell, shell_perf)
**제목:** [CBRD-26678] Add SQL / shell testcase for parallel index build
**작성자:** ssihil
**HEAD SHA:** #3827 `d07fa316d6c2` (Greptile 반영 커밋, 최초 `c59eb5d46d8a`) / #4515 `05363cccc140`
**엔진 PR:** CUBRID/cubrid#7011 (2026-04-27 머지, `cc563c7fd`) -> 이후 CBRD-27235 (#7831, 2026-09-14) 가 인덱스 빌드 정렬을 `btree_sort.c` 로 분리
**JIRA:** CBRD-26678 (Development Subject, Test)
**리뷰 일시:** 2026-10-21
**리뷰 결정:** #3827 Request changes (review 5597241546, bagus-kim 스레드 답글 4334866280) / #4515 Request changes (review 5597241746, 인라인 3건) — 2026-10-21 게시

> **TL;DR** (Blocking): 두 PR 모두 "병렬 진입 조건"을 CBRD-27235 이전 코드(`parallel_sort_page_threshold`, `compute_parallel_degree`, `sort_check_parallelism`)로 계산했다. 지금 develop 의 인덱스 빌드는 `parallel_index_build_page_threshold` (기본 2048 페이지, `test_mode` 가 바꾸지 않음)로 판정하므로, SQL TC 34 케이스와 shell TC 의 "병렬" 빌드는 전부 단일 스레드로 돈다. shell_perf 는 2.7GB 힙이라 실제로 병렬을 탄다.

## Summary

- **변경 요약**: CBRD-26678 병렬 인덱스 빌드에 대한 SQL TC 34 케이스, shell TC 4 시나리오(checkdb, 병렬/단일 대조), shell_perf TC(속도 비교) 추가
- **주요 이슈**: SQL TC, shell TC 가 병렬 경로에 진입하지 않음 (gdb 실측). shell TC 의 직렬 강제 파라미터도 인덱스 빌드와 무관
- **확인 필요 사항**: SQL TC 를 병렬 경로에 넣을 방법(테이블 2048 페이지 이상, 또는 병렬 검증을 shell 로 이동)

---

## Findings

### Blocking (must fix)

1. **#3827 `cbrd_26678.sql` 헤더 31-45행 + 모든 케이스 — 병렬 경로 미진입.** develop 의 `btsort_compute_parallel_degree` (인덱스 빌드 병렬도 계산, `btree_sort.c`) 는 `n_data_pages < parallel_index_build_page_threshold` 이면 0 을 돌려준다. 이 파라미터는 hidden, 기본 2048, 동적 변경 불가이고 `prm_tune_parameters` 의 `test_mode` 분기는 scan(32) / hash join(0) 임계값만 바꾼다. TC 의 테이블은 `tb` 469, `pt` 파티션당 325, `bk` 89 페이지(char(2048) 은 압축됨)라 전부 단일 스레드 -> "병렬로 만든 인덱스가 정확한가" 는 한 케이스도 검증되지 않음. 케이스 31/32(fallback) 도 다른 케이스와 구별되지 않는다.
   ```c
   page_threshold = prm_get_integer_value (PRM_ID_PARALLEL_INDEX_BUILD_PAGE_THRESHOLD);
   page_threshold = MAX (page_threshold, start_degree);
   if (n_data_pages < page_threshold) return 0;
   ```
2. **#4515 `shell/.../cbrd_26678.sh:59`, `:180` — 파라미터가 인덱스 빌드에 영향 없음.** `parallel_sort_page_threshold=0` / `=2147483647` 은 CBRD-27235 이후 쿼리 정렬(ORDER BY 등)에만 쓰인다. 653 페이지 테이블은 두 설정 모두 단일 스레드 -> 시나리오 3 은 직렬 대 직렬 비교, 시나리오 1-2 의 checkdb 도 직렬 인덱스를 검사. `parallel_index_build_page_threshold=0` (병렬) / `=2147483647` 또는 `index_build_parallelism=1` (직렬) 로 바꾸면 653 페이지, 11 섹터, degree 4 로 병렬 진입함을 실측했다. 59행 주석의 "default 2048" 도 `parallel_sort_page_threshold` 기본값(256)과 다르다.

### Non-blocking (should consider)

3. **#4515 `shell_perf/.../cbrd_26678.sh` 헤더 2-21행** — `SORT_INDEX_LEAF`, `compute_parallel_degree` 는 develop 에 없는 이름. 판정 자체는 맞다: `index_build_parallelism=-1` 이 `parallelism` 을 따르므로 `parallelism=1` 이면 직렬, 2.7GB(약 17만 페이지) 힙은 2048 페이지 이상이라 `parallelism=4` 에서 degree 4. 주석만 `btsort_compute_parallel_degree`, `index_build_parallelism` 으로 갱신 권장.
4. **#3827, #4515 PR 본문** — "test_mode=yes 가 parallel_sort_page_threshold 를 0 으로 낮춘다" 는 develop 코드에 없음(`sort_page_threshold_prm` 을 읽기만 하고 바꾸지 않음). 본문의 진입 조건 계산 전체가 #1, #2 와 같은 원인.

### Questions for the author

5. #1 의 해결 방향 (grill: 사실만 짚고 방향은 작성자에게, 예시로 제시):
   - 엔진: `prm_tune_parameters` 의 `test_mode` 분기에서 `parallel_index_build_page_threshold` 도 기본값이면 0 으로 (hash join 과 같은 패턴). 별도 엔진 이슈, CTP sql 전체의 193 페이지 이상 CREATE INDEX 가 병렬로 바뀜.
   - TC: 테이블을 2048 페이지(32MB) 이상, 파티션은 파티션마다 2048 페이지 이상. 255 바이트 이상 문자열은 압축되므로(bk 89 페이지) 짧은 char 컬럼 여러 개로 행 폭을 늘림. degree 2 / 섹터 32 이상이라 케이스 32 의 섹터 부족 fallback 은 만들 수 없음.
   - 이동: 병렬 정확성은 shell TC(임계값 0)로, SQL TC 는 경로 무관 정확성으로 설명 수정.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 첨부 `parallel_index_build.sql` 25 개 | #3827 케이스 1-29 매핑표 | 부분 (모두 직렬 빌드, #1) |
| A/C 1 단일 스레드 대비 빠름 | #4515 shell_perf | 통과 (진입 조건 코드상 성립) |
| A/C 2a-2c, 2e 병렬 빌드 오류 없음 | #3827 | 미충족 (병렬 미진입, #1) |
| A/C 2d fallback | #3827 케이스 31, 32 | 부분 (모든 케이스가 fallback 이라 구별 불가) |
| checkdb 구조 검사, 병렬/직렬 대조 | #4515 shell | 미충족 (#2) |

TC 파일: 케이스와 answer 짝 일치(`answer`, `answer_cci` 각 1673행), 헤더 주석에 `;` 없음, `autocommit off` 문구는 지시어 두 줄에만 있음.

## Runtime Verification

- develop optdebug `5b1867174` (btree_sort.c 병렬도 코드는 origin/develop `620ceaf6a` 와 동일), C/S 서버에 gdb attach, `btree_sort.c:4690/4633/4697/4712` 브레이크포인트. 증거 scratch 는 2026-10-21 삭제, 수치는 아래와 같음
  - `test_mode=yes, parallelism=4` (CTP sql 과 같은 조건): tb 469 / bk 89 / pt 파티션 325 x4 / shell 테이블 653 페이지 -> 전부 `page_threshold=2048` 에서 직렬
  - 위 + `parallel_index_build_page_threshold=0`: tb, pt 4 파티션, shell 테이블 병렬(degree 4, workers reserved), bk 는 섹터 2 < 4 로 fallback
- CI / CTP 실행 없음 (판정이 코드 경로 진입 여부라 gdb 실측으로 대체).

## Existing Comments

| 코멘트 | 내용 | 상태 |
|---|---|---|
| Greptile 4333285105 (#3827:85) | covered scan 은 키만 읽어 엔트리-행 연결 오류를 못 잡음 | d07fa31 에서 반영, 작성자 답글 |
| Greptile 4333285117 (#3827:200) | `lower(cola)` 데이터가 숫자뿐이라 함수 미적용 오류를 못 잡음 | d07fa31 에서 반영(lc 테이블), 작성자 답글 |
| bagus-kim 4334380243 (#3827:32) | 2048 페이지 임계값으로 tb/pt/md/sm 모두 단일 스레드 아닌지 (Finding #1 과 같음) | 미응답, bagus-kim 은 APPROVE |
| swi0110 #4515 APPROVE | 본문 없음 | - |
