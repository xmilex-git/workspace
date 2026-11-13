# PR #8311 코드 리뷰 보고서 (2차)

**PR:** [CUBRID/cubrid#8311](https://github.com/CUBRID/cubrid/pull/8311)
**제목:** [CBRD-27787] Keep parallel sort with a serial put from running slower than a serial sort on a small data buffer
**작성자:** shparkcubrid
**HEAD SHA:** `8f644ec56` (develop merge-base `d93145bdb`, 1차 리뷰 head `a3deaac02`)
**JIRA:** CBRD-27787 (첨부 없음) / 연관: CBRD-27684 (PR #8200)
**TC PR:** CUBRID/cubrid-testcases#3918 (`tc/pr-8311` `e84f553fc`) / cubrid-testcases-private-ex#4609 (변경 없는 draft)
**리뷰 일시:** 2026-10-29
**리뷰 결정:** 엔진 PR #8311 Approve / TC PR #3918 Approve (NIT 1개) / private-ex #4609 리뷰 없음

> **TL;DR** (Non-blocking): 1차 질문(#8200 이후 재측정)에 작성자가 develop 위에서 다시 재고, 수정 방식을 바꿨습니다. 워커가 메인의 private LRU(트랜잭션별 버퍼 교체 리스트)를 빌리던 방식을 빼고, 병합이 읽은 run 페이지를 LRU 맨 아래로 보냅니다. 새 코드에서 결함을 찾지 못했고, CI sql 실패 11건은 이 PR과 무관합니다.

## Summary

- **변경 요약**: 커밋 1-2(병합 큐를 4개 run까지만 돌리고 메인이 마지막 병합에서 바로 put)는 1차와 같습니다. 커밋 3 `8f644ec56`이 private LRU 빌리기를 지우고 `pgbuf_copy_page_to_area_lru_bottom`을 추가해 `sort_read_area`가 씁니다.
- **주요 이슈**: 없음
- **확인 필요 사항**: TC 헤더 주석 한 줄이 지운 방식을 설명함(NIT).

---

## Findings

### Non-blocking (should consider)
- TC #3918 `cases/cbrd_27787.sql:6-7` — 헤더가 "the workers keep the input pages in the main thread's private LRU list"라고 적지만, 커밋 `8f644ec56`이 그 방식을 지웠습니다. NIT.

## 새 코드 확인 (커밋 3)

- 버퍼에 있는 페이지: `pgbuf_search_hash_chain`이 BCB(버퍼 제어 블록) mutex를 잡은 채 돌려줍니다. 새 함수는 fix 수 0, 대기자 없음, LRU zone일 때만 `pgbuf_move_bcb_to_bottom_lru`를 부릅니다. 잠금 순서(BCB mutex -> LRU list mutex)는 기존 호출부 `pgbuf_unlatch_bcb_upon_unfix`와 같고, 희생자 선택은 list mutex를 쥔 채 BCB를 trylock하므로 교착이 없습니다. VOID zone은 건너뛰어 `assert (false)` 분기에 가지 않습니다.
- 버퍼에 없는 페이지: fix -> `pgbuf_mark_page_for_lru_bottom`(통계 수집 스캔이 쓰는 기존 표시) -> unfix. 마지막 unfix가 맨 아래로 옮깁니다.
- 바닥으로 내린 run 페이지를 다음 패스가 출력으로 다시 쓸 때 `sort_write_area`는 `pgbuf_copy_from_area` -> `NEW_PAGE` fix라 디스크에서 다시 읽지 않습니다.
- `sort_read_area` 호출부 8곳(`sort_inphase_sort`, `sort_exphase_merge[_elim_dup]`, `sort_put_result_from_tmpfile`)은 모두 run 페이지를 한 번씩만 읽습니다.
- develop drift: merge-base 이후 `external_sort.c` / `page_buffer.[ch]`를 건드린 develop 커밋 없음.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC1: 512M에서 병렬이 직렬보다 느리지 않음 | PR 표(develop `82d86d25b`, #8200 포함): 6개 질의 모두 PR 병렬 < develop 직렬, ioread 감소 | 충족 |
| AC2: 8G에서 병렬 이득 유지 | PR 본문: develop/PR 모두 ioread 0, 시간 차이 변동 범위 | 충족 |
| AC3: 결과·순서 동일 | PR 33개 질의, 4세션 동시, TC #3918 CI 통과 | 충족 |
| 1차 질문: #8200 이후 재측정 | 재측정 후 방식 변경, 표 갱신, 키가 아닌 컬럼 280B 경우 포함 | 충족 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| ORDER BY LIMIT / OFFSET / orderby_num (PARALLEL 1/4/8/16) | #3918 섹션 1 | 통과 |
| 분석함수 | #3918 섹션 2 | 통과 |
| GROUP BY 정렬 | #3918 섹션 3 | 통과 |
| DISTINCT + ORDER BY + LIMIT (`SORT_ELIM_DUP` 분기) | `6ef3c5961`에서 추가(1차 요청 반영) | 통과 |
| 병렬 정렬 실행 확인 | 섹션 4 trace, PARALLEL(8)에만 `parallel workers` 줄(greptile 요청 반영) | 통과 |

- case마다 answer가 있고 헤더 주석에 `;`가 없습니다. `pad`는 바깥에서 `sum(length(pad))`로 집계해 정렬 입력에 남습니다.
- private-ex #4609는 변경 없는 draft라 리뷰하지 않습니다.

## Runtime Verification

- CI gha-ci run 40824940519 (head `8f644ec56`, `tc/pr-8311` `e84f553fc`, private-ex `b5c2c5fa`): build debug/release, medium(975), shell(3515) 통과. sql은 17691개 중 11건 실패.
- sql 실패 11건은 모두 `sql/_36_guava/cbrd_27381/*`입니다. 이 TC는 testcases develop에 `876b70cb1`(10-29 05:18Z)로 먼저 머지됐고, 엔진 수정 PR #8209는 아직 열려 있습니다. 무관한 PR #8318(run 40827759161)도 같은 11건이 실패합니다. 이 PR과 무관합니다.
- `sql/_36_guava/cbrd_27787/cases/cbrd_27787.sql`: shard 09 debug에서 통과(5.5초).
- 1차 리뷰어 smoke(head `a3deaac02`)는 커밋 3 이전 코드라 이번 판정 근거로 쓰지 않았습니다. 이번 라운드에 로컬 실행은 하지 않았습니다.
- 확인하지 못한 것: 성능 수치는 작성자 측정값이며 리뷰어가 다시 재지 않았습니다. hash GROUP BY spill의 부분 정렬 경로도 따로 돌리지 않았습니다.
