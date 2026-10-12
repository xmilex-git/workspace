# PR #8105 코드 리뷰 보고서 (재리뷰)

**PR:** [CUBRID/cubrid#8105](https://github.com/CUBRID/cubrid/pull/8105)
**제목:** [CBRD-27557] Fix hash join split when temp_file_memory_size_in_pages is 0
**작성자:** youngjinj
**HEAD SHA:** `dbea5c2de` (develop merge-base `58b49b39f`. 코드 커밋은 `91a8ec8d1`, `c0deddaef` 2개, 나머지는 develop 머지)
**JIRA:** CBRD-27557 (Correct Error, Open, 첨부 없음) / 연관: CBRD-25717 (assert 도입, Regress), CBRD-26666 (Relates), CBRD-27569 (PR 본문이 근본 해결로 지목. JIRA 링크 없음)
**TC PR:** CUBRID/cubrid-testcases#3646 (`tc/pr-8105` `b1ff1933b`, 빈 draft) / CUBRID/cubrid-testcases-private-ex#4321 (`tc/pr-8105` `8f7b05655`)
**리뷰 일시:** 2026-10-12 (1차 2026-10-10, Request changes)
**리뷰 결정:** 엔진 PR Approve / private-ex#4321 Approve / #3646 리뷰 없음 (빈 draft)

> **TL;DR** (Non-blocking): 1차 Blocking (직렬 split reopen 실패 시 에러 코드 유실) 이 `c0deddaef` 로 고쳐졌다. head release 에서 split 중 `KILL QUERY` 40회가 모두 "Has been interrupted" 로 끝났다 (수정 전 직렬 20회 중 5회 부분 count). private-ex#4321 은 제안한 page buffer 고갈 구성(9-10)을 받아들였고 head optdebug 에서 1-10 모두 OK. 남은 것은 JIRA Description 보완과 CBRD-27569 링크뿐이다.

## Summary

- **변경 요약**: 1차 내용에 더해, 직렬 split `hjoin_split_qlist` 의 세 실패 분기(파티션별 임시 리스트 reopen, overflow 튜플 reopen, `qfile_open_list`)가 `error` 를 설정하고, 루프가 오류로 끝나면 파티션 리스트 병합을 건너뛴다
- **주요 이슈**: 없음
- **확인 필요 사항**: JIRA Description 의 "release 빌드에서는 발생하지 않는다" 보완, CBRD-27569 링크 (1차 요청, 미반영)

---

## Findings

없음

`c0deddaef` 검토 내용:
- 병합 생략 후 임시 리스트는 호출자 `hjoin_build_partitions` 의 cleanup 이 `qfile_close_list` -> `qfile_destroy_list` -> 해제한다. 누수 없음.
- 병렬 split `split_task::execute` 도 `has_error` 이면 병합을 건너뛰므로 주석의 "as the parallel split does" 는 사실이다.
- `qfile_open_list` 실패 분기의 `assert_release_error` 는 release 에서 `ER_FAILED_ASSERTION` 을 설정하므로 `error` 가 `NO_ERROR` 로 남지 않는다.

## JIRA -> Engine PR

기준: JIRA Expected Result 가 JIRA 재현 조건에서 성립하고, design.md 의 변경과 미정 항목이 처리되었는가.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: 두 질의 모두 100000 (membuf 0, 256k, parallel(8) / 직렬) | gha-ci run 38204357319 `membuf_config` 3-4 OK, 리뷰 실행 3-4 OK | 충족 |
| design.md 변경 / 미정 항목 | 첨부 없음. PR 본문 Implementation 이 대신함 | 해당 없음 |
| PR 목적 2: page buffer 고갈 방지 (membuf 0, 파티션 1587) | 1차 A/B: develop release 직렬/병렬 300 s 무응답, PR 1.6 s. 이번 TC 9-10 OK | 충족 |
| 1차 Blocking: 취소된 직렬 split 이 부분 결과 반환 | `c0deddaef`. 리뷰 실행 직렬 20/20 interrupted | 충족 |

같은 결함을 기술한 다른 JIRA 는 없다. JIRA Description 은 아직 "release 빌드에서는 발생하지 않는다" 이고 CBRD-27569 링크도 없다 (2026-10-06 이후 변경 없음).

판정: 충족. JIRA 보완은 승인 조건이 아니라 요청으로 남긴다.

## TC PRs

기준: 시나리오가 JIRA test.md 에 있거나 TC PR(본문 또는 변경 파일)이 다루면 통과. test.md 가 없어 JIRA Repro 와 PR 본문의 두 목적을 시나리오로 삼는다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| JIRA Repro: membuf 0, 256k (파티션 25), parallel(8) 과 직렬 | #4321 disk-only 3-4 | 통과 |
| page buffer 고갈: membuf 0, data_buffer_size 16M, 4k (파티션 1587) | #4321 9-10 (`1102b4121`), csql `timeout 120` (`8f7b05655`) | 통과 |

TC 파일 검토: #4321 은 shell 케이스 1개만 바꾼다. 결과는 `write_ok`/`write_nok` 로 남는다. 9-10 은 `change_db_parameter "data_buffer_size=16M"` 뒤 `set_membuf 0` 의 재시작으로 반영되고, 16M / 16K 페이지 = 1024 frame < 파티션 1587 이다. 회귀 시 무응답은 `timeout` 으로 NOK 가 된다. 작성자 답변(회귀 변형 optdebug 에서 `pgbuf_compute_lru_vict_target` assert 로 NOK)과 일치하는 구성이다. #3646 은 변경 없는 draft 다.

판정: 통과. #4321 Approve, #3646 리뷰 없음.

## Runtime Verification

- CI (head): gha-ci run 38204357319, 엔진 `dbea5c2de`. build debug/release, sql, medium, shell 통과. 단 shell 은 TC `2db4bf5c1` (9-10 추가 전) 로 돌아 `membuf_config` 1-8 만 검사했다.
- 리뷰 실행 1 (TC 9-10 보완): `just ctp shell _40_guava/cbrd_25717/cbrd_25717_membuf_config`, 엔진 `dbea5c2de` optdebug (CI tarball, libcubrid sha256 `19c72500...`), TC private-ex `tc/pr-8105` `8f7b05655`, cubridci 이미지. 1-10 모두 OK, 코어 없음, 케이스 31 s. `[disk-only-small-buffer] workers=8 parallel_count=100000 serial_count=100000`.
- 리뷰 실행 2 (1차 Blocking 재현): 엔진 `dbea5c2de` release (CI tarball), `temp_file_memory_size_in_pages=0`, `data_buffer_size=16M`, 4k (파티션 1587). 무취소 기준 직렬 SPLIT 956 ms, 병렬(8) SPLIT 1606 ms, 둘 다 100000. split 중 `KILL QUERY` (시작 후 0.03~0.85 s) 직렬/병렬 번갈아 20회씩: 40회 모두 "Has been interrupted", 부분 count 0, 무응답 0. 직렬 로그마다 `page_buffer.c` `-4` 뒤 `-1124` 가 있다 (수정 전 부분 count 5회에는 `-1124` 가 없었다).
- 증거: `.git_ignored_dir/scratch/pr8105/rereview/laneA-ctp/evidence/`, `.../laneB-cancel/evidence/`. 1차 증거는 `.git_ignored_dir/scratch/pr8105/evidence/`.

## Existing Comments

| 코멘트 | 상태 |
|---|---|
| 1차 inline r4238031514 (reopen 실패 에러 유실) | 작성자 답변 4244702590, `c0deddaef` 로 수정. 리뷰 실행으로 확인. 해결됨 |
| private-ex#4321 inline r4238031628 (page buffer 고갈 구성) | 작성자 답변 4244888536, 9-10 추가. 리뷰 실행으로 확인. 해결됨 |
| 1차 top-level (JIRA Description 보완, CBRD-27569 링크) | 답변 없음, JIRA 변경 없음. Approve 본문에서 다시 요청 |
