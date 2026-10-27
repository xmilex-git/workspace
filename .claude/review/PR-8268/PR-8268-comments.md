# PR #8268 게시용 리뷰 코멘트

게시 전 사용자 확인 필요. 각 리뷰의 `commit_id` 는 그 PR 의 head SHA.

## CUBRID/cubrid#8268

- event: APPROVE
- commit_id: `0b8b83377561f881266fa9f52955956f8fc069d1`
- 인라인 코멘트: 없음

본문:

```text
`hjoin_check_partition` 이 고르는 쪽이 `hjoin_init_context` 가 해시 테이블을 만드는 쪽과 같아, LEFT/RIGHT OUTER, SEMI, ANTI 조인은 이제 빌드 입력의 행 수로 파티션 수를 정합니다. o 2001 행 LEFT OUTER JOIN i 200001 행을 CI debug 빌드 두 개로 돌려 봤습니다. develop(4781495f0)은 SPLIT 없이 `file` 로 BUILD 에 1.8-3.3 초가 걸리고, 이 PR(0b8b83377)은 파티션 3 개, `memory+skip` 으로 12-17 ms 가 걸립니다. 결과 행은 USE_NL 과 같습니다. prepare 해 둔 해시 조인을 `max_hash_list_scan_size=0` 으로 바꾼 뒤 execute 하면 develop debug 빌드는 cub_server 가 assert 로 내려가고, 이 PR 은 `method: file` 로 끝까지 돕니다. `temp_file_memory_size_in_pages=0` 으로 띄운 서버에서도 결과 행은 같았습니다.
```

## CUBRID/cubrid-testcases#3873

- event: APPROVE
- commit_id: `7f26b3a0c59b2a192d96ed12317c972526b92a8f`
- 본문: 없음

## CUBRID/cubrid-testcases-private-ex#4561

- event: APPROVE
- commit_id: `63d9b88df4d895ba8f1ec153c745dcfc65fb722b`
- 본문: 없음
