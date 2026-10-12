# PR #8105 게시용 리뷰 코멘트 (재리뷰, 2026-10-12)

사용자 승인: "딱히 더 볼거없으면 approve 처리해도돼" (2026-10-12). 리뷰마다 `commit_id` 는 해당 PR head.
1차(2026-10-10) 게시분: 엔진 review 5479451253 (REQUEST_CHANGES), private-ex#4321 review 5479451451 (COMMENT).

---

## 1. CUBRID/cubrid#8105 (엔진)

- event: APPROVE
- commit_id: `dbea5c2de51c89743feba8ecf596f62ee4a0daba`

### top-level body

c0deddaef 확인했습니다. 실패 분기에서 error 를 받고, 오류일 때 병합을 건너뛰어도 임시 리스트는 hjoin_build_partitions 의 cleanup 에서 정리되는 것 확인했습니다.
head release 빌드(temp_file_memory_size_in_pages=0, data_buffer_size=16M, 4k 파티션 1587개)로 split 중 kill query 를 직렬/병렬 20회씩 다시 해 보니 40회 모두 "Has been interrupted" 로 끝났고, 에러 없이 count 가 나온 경우는 없었습니다.

JIRA 는 지난번 말씀드린 Description 보완(파티션 수가 page buffer frame 수를 넘으면 release 에서도 응답이 없어지는 내용)과 CBRD-27569 링크만 반영 부탁드립니다.

---

## 2. CUBRID/cubrid-testcases-private-ex#4321 (TC)

- event: APPROVE
- commit_id: `8f7b05655232a376cf4e8bed8af3eadad7c5a407`

### top-level body

9-10 구성과 timeout 추가 확인했습니다. 엔진 PR head(`dbea5c2de`) optdebug 로 이 케이스를 돌려 보니 1-10 모두 OK 였고, disk-only-small-buffer 도 병렬 workers=8, 병렬/직렬 모두 100000 이었습니다.
엔진 PR 의 gha-ci shell 은 9-10 추가 전 커밋(`2db4bf5c1`)으로 돌았던 것이라, 위 결과는 같은 CI 이미지와 CI 빌드로 로컬 컨테이너에서 확인한 것입니다.

---

## 3. CUBRID/cubrid-testcases#3646

리뷰 없음 (변경 없는 빈 draft).
