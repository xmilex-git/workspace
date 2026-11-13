# PR-8353 post-ready comments

## CUBRID/cubrid#8353 (engine)

- review event: APPROVE
- commit_id: 6b0ca5566818213e7b65040102051b4145ce226e
- inline: 없음

본문:

단일 컬럼 SHORT·INTEGER·BIGINT 인덱스에서 같은 형의 검색 키만 키 이미지를 바로 비교하는 변경을 확인했습니다. leaf 이미지 위치는 btree_read_record_without_decompression 이 OID, 고유 인덱스의 class OID, MVCC 삽입·삭제 ID 를 건너뛰는 순서와 같고, fence 레코드도 btree_write_record 로 같은 배치라 같은 자리를 읽습니다. 내림차순 인덱스는 btree_compare_key 가 단일 컬럼 키에서 뒤집는 것과 같은 답을 내고, 변환이 있는 경계·다중 컬럼 키·page_bounds 탐색은 기존 경로로 갑니다. gha-ci run 41392690041 (optdebug, tc/pr-8353) 에서 sql·medium·shell 이 모두 통과했고 새 TC 도 ok 입니다.

## CUBRID/cubrid-testcases#3969

- review event: COMMENT
- commit_id: 68030a99a50ef9ad89d3cb65f54fbd1c983c68c4
- inline: 없음 (Greptile 의 cbrd_27862_integral_key_search.sql:73 스레드와 같은 지적이라 새 인라인을 달지 않음)

본문:

Case 1, 3, 4 와 rowpath 수정은 확인했습니다. Case 2 의 rng_* 다섯 검사는 Greptile 이 짚은 대로 인덱스 쪽이 행을 하나도 찾지 못하면 sum(id) 가 NULL 이 되어 비교식도 NULL 이 되고, 그 행이 불일치로 세지지 않습니다. 양쪽 sum(id) 를 coalesce(sum(id), 0) 으로 감싸면 행을 모두 놓치는 경우도 잡을 수 있는데, 반영해 주시면 어떨까요? 기대값은 지금처럼 0 이라 답안은 바뀌지 않을 것으로 보입니다.

## CUBRID/cubrid-testcases-private-ex#4679

- 리뷰 없음: 봇 init 커밋만 있고 파일 변경이 없음 (닫으면 TC Merge Gate 가 풀림)
