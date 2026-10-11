# PR #8105 게시용 리뷰 코멘트

게시 전 사용자 확인 필요. 리뷰마다 `commit_id` 는 해당 PR head.

---

## 1. CUBRID/cubrid#8105 (엔진)

- event: REQUEST_CHANGES
- commit_id: `b68bfc22d3c3a37f6cde3305f0a3be332fee95c2`

### top-level body

temp_file_memory_size_in_pages=0 에서 split 의 파티션별 임시 리스트를 튜플마다 reopen/close 하고, assert 를 membuf 가 있을 때로 좁힌 변경 확인했습니다. release 빌드로 data_buffer_size=16M, max_hash_list_scan_size=4k (파티션 1587개) 조건을 돌려 보니 develop(`ecb26cda1`)은 직렬/병렬 모두 `pgbuf_allocate_bcb` 에서 빈 frame 을 기다리며 300초 넘게 응답이 없었고, 이 PR 은 1.6초에 100000 을 돌려줬습니다. 직렬 split 의 reopen 실패 처리만 인라인으로 남겼습니다.

확인 부탁드립니다
- JIRA Description 에는 "release 빌드에서는 발생하지 않는다" 로 되어 있는데, 파티션 수(병렬은 x 워커 수)가 page buffer frame 수를 넘으면 release 에서도 응답이 없어진다는 내용을 추가하면 좋을 것 같습니다.
- PR 본문에서 근본 해결로 언급하신 CBRD-27569 를 JIRA 에서도 CBRD-27557 과 링크해 주시면 좋겠습니다.

### inline: `src/query/query_hash_join.c` line 1779 (RIGHT)

reopen 이 실패하면 `error` 가 `NO_ERROR` 인 채로 `break` 해서, 루프 뒤 `if (scan_code == S_ERROR || error != NO_ERROR)` 를 지나 `NO_ERROR` 로 반환되는 것으로 보입니다.
membuf 0 에서는 이 reopen 이 튜플마다 `pgbuf_fix` 를 하고, `pgbuf_fix` 진입에서 취소 플래그를 검사하며 지우기 때문에 split 중 취소가 여기서 소비되면 남은 튜플이 빠진 채 조인이 끝납니다.
release 빌드로 아래를 20회 해 보니 5회가 에러 없이 16413, 84236 같은 count 를 돌려줬습니다 (병렬은 20회 모두 interrupted).
```sql
-- temp_file_memory_size_in_pages=0, data_buffer_size=16M, parallel_hash_join_page_threshold=0, t_mb 100000행
set system parameters 'max_hash_list_scan_size=4k';
select /*+ recompile use_hash no_parallel_scan no_parallel_subquery no_parallel_hash_join */ count (*) from t_mb a, t_mb b where a.c1 = b.c1;
-- split 중 다른 세션에서 kill query <tran_index>;
```
병렬 쪽처럼 에러 코드를 받아야 할 것 같습니다.
```suggestion
      error = qfile_reopen_list_as_append_mode (thread_p, temp_part_list_id[part_id]);
      if (error != NO_ERROR)
```
같은 함수의 overflow 튜플 reopen 과 `qfile_open_list` 실패 분기도 같은 모양이라, 같이 보시면 좋을 것 같습니다.

### 기존 코멘트

- greptile 4192501136 (membuf 0 회귀 TC): 작성자 답변으로 해결됨. 추가 게시 없음.
- greptile 요약 6011256062: diff 와 무관. 대응 안 함.

---

## 2. CUBRID/cubrid-testcases-private-ex#4321 (TC)

- event: COMMENT
- commit_id: `1768a1b71e2361c0d2cfdc9f08787e184e375993`

### top-level body

disk-only 구성 복원과 원인 설명 정정 확인했습니다. 엔진 PR head(`b68bfc22d`) CI 에서 1-8 모두 OK 였습니다.

### inline: `shell/_40_guava/cbrd_25717/cbrd_25717_membuf_config/cases/cbrd_25717_membuf_config.sh` line 147 (RIGHT)

disk-only 구성은 파티션이 25개라 develop release 에서도 통과하는데, 엔진 PR 본문의 두 번째 문제(page buffer 고갈)는 파티션 수가 frame 수를 넘어야 드러나는 것 같습니다.
release 빌드로 data_buffer_size=16M, 4k(파티션 1587개)를 돌려 보면 develop 은 직렬/병렬 모두 300초 넘게 응답이 없고, 엔진 PR 은 약 2초에 100000 이었습니다.
마지막에 아래 구성을 하나 더 두는 것은 어떨까요? 회귀하면 응답이 없어지니 `run_join` 의 csql 을 `timeout` 으로 감싸는 것도 같이 고려해 주시면 좋겠습니다.
```bash
# 9-10. disk-only with a small data buffer: 4k gives 1587 partitions, more than the page buffer frames
change_db_parameter "data_buffer_size=16M"
set_membuf 0
check_config "disk-only-small-buffer" t_mb_big 4k 100000
```

---

## 3. CUBRID/cubrid-testcases#3646

리뷰 없음 (변경 없는 빈 draft).
