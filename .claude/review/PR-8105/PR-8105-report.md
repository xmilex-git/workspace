# PR #8105 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8105](https://github.com/CUBRID/cubrid/pull/8105)
**제목:** [CBRD-27557] Fix hash join split when temp_file_memory_size_in_pages is 0
**작성자:** youngjinj
**HEAD SHA:** `b68bfc22d` (develop merge-base `ecb26cda1`. 코드 커밋은 `91a8ec8d1` 1개, 나머지는 develop 머지)
**JIRA:** CBRD-27557 (Correct Error, Open, 첨부 없음) / 연관: CBRD-25717 (assert 도입, Regress), CBRD-26666 (Relates), CBRD-27569 (PR 본문이 근본 해결로 지목. JIRA 링크 없음)
**TC PR:** CUBRID/cubrid-testcases#3646 (`tc/pr-8105` `58c4d4e76`, 빈 draft) / CUBRID/cubrid-testcases-private-ex#4321 (`tc/pr-8105` `1768a1b71`)
**리뷰 일시:** 2026-10-10
**리뷰 결정:** 엔진 PR Request changes / private-ex#4321 Comment (page buffer 고갈 구성 제안) / #3646 리뷰 없음 (빈 draft)

> **TL;DR** (Blocking): JIRA 재현(debug assert)과 develop release 의 page buffer 고갈 무응답(데이터 버퍼의 페이지 슬롯인 frame 이 모두 고정되어 질의가 멈춤)이 모두 해결된다. 다만 직렬 split `hjoin_split_qlist` 의 새 reopen 실패 분기가 에러 코드를 버린다. 그래서 membuf 0 (`temp_file_memory_size_in_pages=0`, 임시 리스트에 메모리 버퍼 페이지가 없음) 에서 split 중 취소된 질의가 적은 행을 정상 결과로 돌려준다 (리뷰 실행 20회 중 5회). 한 줄 수정이면 머지 가능하다.

## Summary

- **변경 요약**: split 단계(해시 조인이 두 입력을 해시 키로 파티션 리스트에 나눠 쓰는 단계)의 파티션별 임시 리스트(파티션 리스트로 옮기기 전 튜플을 모으는 리스트)를 튜플마다 `qfile_reopen_list_as_append_mode` -> `qfile_add_tuple_to_list` -> `qfile_close_list` 로 쓰고, "임시 리스트는 디스크 파일이 없다" assert 를 membuf 가 있을 때로 한정
- **주요 이슈**: `query_hash_join.c:1779` reopen 실패 시 에러 코드 유실 -> 취소된 질의가 부분 결과를 반환
- **확인 필요 사항**: JIRA Description 에 release 무응답(파티션 수가 page buffer frame 수를 넘는 경우) 보완, CBRD-27569 링크

---

## Findings

### Blocking (must fix)

- `src/query/query_hash_join.c:1779` -- 직렬 split 의 새 reopen 실패 분기가 반환값을 `error` 에 담지 않고 `break` 한다 -> 루프 뒤 `if (scan_code == S_ERROR || error != NO_ERROR)` 를 지나 `NO_ERROR` 를 반환한다 -> 남은 튜플이 파티션에 들어가지 않은 채 조인이 진행되어, 취소된 질의가 적은 행을 정상 결과로 돌려준다.
  ```c
  if (qfile_reopen_list_as_append_mode (thread_p, temp_part_list_id[part_id]) != NO_ERROR)
    {
      break;		/* error_exit */
    }
  ```
  membuf 0 에서 이 reopen 은 튜플마다 `pgbuf_fix` (페이지 버퍼 frame 을 잡는 함수) 를 부른다. `pgbuf_fix` 는 진입 시 `logtb_is_interrupted (thread_p, true, ...)` 로 사용자 취소를 검사하고 그 플래그를 지운다. 리뷰 실행(head release, membuf 0, 4k)에서 split 중 `KILL QUERY` 를 보내면 직렬은 20회 중 5회가 에러 없이 14060~86886 을 돌려주었다. 그 5회의 서버 로그에는 `page_buffer.c:2254 -4` 만 있고 `-1124` (질의 실행 오류) 가 없다. 병렬은 20회 모두 `-4` 로 끝났다. 병렬 경로 `split_task::execute` 는 같은 실패를 `handle_error` 로 올리기 때문이다. 수정: `error = qfile_reopen_list_as_append_mode (...)` 로 받은 뒤 `break`.

## JIRA -> Engine PR

기준: JIRA Expected Result 가 JIRA 재현 조건에서 성립하고, design.md 의 변경과 미정 항목이 처리되었는가.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: 두 질의 모두 100000 (temp_file_memory_size_in_pages=0, 256k, parallel(8) / 직렬) | CI run 37438033455 shell shard 26 `membuf_config` 3-4 OK (같은 SQL, 같은 설정) | 충족 |
| design.md 변경 / 미정 항목 | 첨부 없음. PR 본문 Implementation 이 대신함 | 해당 없음 |
| PR 목적 2: page buffer 고갈 방지 (membuf 0, 파티션 수 x 워커 수 frame 고정) | 리뷰 A/B (release, data_buffer_size 16M, 파티션 1587): develop 직렬/병렬 모두 300 s 무응답, head 1.6 s 에 100000 | 충족 |

같은 결함을 기술한 다른 JIRA 는 없다 (JQL `temp_file_memory_size_in_pages` / `split_task`). CBRD-27569 는 split 구조 개편이며 이 PR 의 assert 를 없애는 근본 해결이다.

판정: 충족. Finding 1 은 JIRA 범위 밖의 새 결함이라 여기에는 반영하지 않는다.

## TC PRs

기준: 시나리오가 JIRA test.md 에 있거나 TC PR(본문 또는 변경 파일)이 다루면 통과. CBRD-27557 에 test.md 가 없어 JIRA Repro 와 PR 본문의 두 목적을 시나리오로 삼는다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| JIRA Repro: membuf 0, 100000행 self join, 256k (파티션 25), parallel(8) 과 직렬 | private-ex#4321 disk-only 3-4 주석 해제 | 통과 |
| page buffer 고갈 (membuf 0, data_buffer_size 16M, 4k -> 파티션 1587) | TC 없음. 리뷰 A/B 로만 확인 | 미포함 (#4321 에 구성 추가 제안) |

TC 파일 검토: #4321 은 shell 케이스 1개만 바꾼다. 결과는 `write_ok`/`write_nok` 로 남으므로 answer 파일이 없다. PR 본문 표(develop debug 서버 종료, PR debug OK workers=8 100000)는 CI 와 일치한다. #3646 은 변경 없는 draft 라 닫으면 된다.

판정: 부분. JIRA Repro 는 통과하고, page buffer 고갈 구성은 제안으로 남긴다 (필수 아님). #3646 은 리뷰 없음.

## Runtime Verification

- CI (head): run 37438033455, 엔진 `b68bfc22d` optdebug, TC `tc/pr-8105` (public `58c4d4e76`, private-ex `1768a1b71`). build debug/release, sql, medium, shell 통과. shard 26 `cbrd_25717_membuf_config` 1-8 OK.
- CI (fail-before): run 37421351718 (#8103, develop 엔진 `0587d1bbe` optdebug, private-ex `tc/pr-8103` `f2c5574ba`). `membuf_config` 3-6 NOK, 코어 발생.
- 리뷰 A/B (release, `temp_file_memory_size_in_pages=0`, `data_buffer_size=16M`, 100000행 self join): develop `ecb26cda1` (gha-ci run 37428243655) 와 head `b68bfc22d` (run 37438033455) 의 release tarball.

  | 조건 | develop `ecb26cda1` | head `b68bfc22d` |
  |---|---|---|
  | 256k (파티션 25), 직렬 / parallel(8) | 100000 (SPLIT 27 / 25 ms) | 100000 (SPLIT 72 / 97 ms) |
  | 4k (파티션 1587), 직렬 | 300 s 무응답. 질의 스레드가 `pgbuf_allocate_bcb` 에서 빈 frame 대기 (`hjoin_split_qlist` -> `qfile_add_tuple_to_list` -> `file_create_temp`) | 100000 (1.63 s, SPLIT 1376 ms) |
  | 4k (파티션 1587), parallel(8) | 300 s 무응답. split 워커 2개가 `pgbuf_allocate_bcb` 대기. 클라이언트 종료 뒤에도 풀리지 않아 서버를 SIGTERM 으로 내림 | 100000 (1.65 s, SPLIT 1427 ms) |

- 취소 재현 (head `b68bfc22d` release, 같은 설정, 4k, split 중 `KILL QUERY`, 직렬/병렬 번갈아 20회씩): 직렬은 interrupted 13, 정상 100000 2 (질의 종료 뒤 도착), 부분 count 5 (84236, 16413, 86886, 14060, 86313). 병렬은 20회 모두 interrupted. 증거 `.git_ignored_dir/scratch/pr8105/evidence/cancel/`.

## Existing Comments

| 코멘트 | 상태 |
|---|---|
| greptile 4192501136 (membuf 0 회귀 TC 요청) | 작성자 답변 4192530013 (private-ex membuf_config 가 담당). 해결됨 |
| greptile 요약 6011256062 ("로그 버퍼 슬롯 교체와 직접 읽기 경로의 동기화 문제") | 이 PR 의 diff 와 무관 (develop 머지 쪽 변경으로 보임). 대응 안 함 |
