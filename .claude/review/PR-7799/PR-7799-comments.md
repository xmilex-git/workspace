# PR-7799 post-ready comments

## CUBRID/cubrid#7799 (engine)

- event: COMMENT
- commit_id: 84097c475a614044546e9a95213b1e64ce3e5345
- inline: 없음

### top-level body

조인 플랜의 판정을 `skip_groupby` 에 두었다가 최종 플랜을 고른 뒤 `qo_set_groupby_skip` 으로 인덱스 플래그에 옮기는 흐름을 읽었습니다. 버려진 후보가 공유 플래그를 남기지 않는 것도 확인했습니다. 오답이나 assert 로 이어지는 경로는 찾지 못했습니다.

이 브랜치가 마지막으로 머지한 develop 은 `82d86d25b` 입니다. 그 뒤 develop 에 `722f5b6b6` (CBRD-27664) 가 들어왔습니다. 이후 executor 는 첫 spec 의 `groupby_skip` 이 켜져 있으면 스캔하면서 바로 집계합니다. `is_groupby_skip_parallel` 은 `scan_ptr` 를 보지 않으므로, 이 PR 의 조인 플랜도 outer 인덱스 스캔이 병렬로 돕니다. 이 head 를 develop `4f1a68c1e` 위에 머지해 optdebug 로 빌드해 봤습니다. 200,000행 outer 위의 inner / left outer / 3-table / HAVING / ORDER BY LIMIT / overflow chain outer 조인을 돌렸습니다. 결과는 직렬, 병렬, `use_hash` 세 가지가 모두 같았습니다. 다만 그 빌드로 `tc/pr-7799` 를 돌리면 `20158_table_schema2` 가 NOK 입니다. 출력은 develop TC 답(CBRD-27664 가 `66e5bdbd4` 에서 고친 답)과 같습니다. 엔진과 TC 를 develop 에 sync 하고, 이 파일은 develop 답을 쓴 뒤 `/run all` 을 다시 돌려 주시면 좋겠습니다.

확인 부탁드립니다
- JIRA 의 Acceptance Criteria 에 TPC-H SF10 Q01~Q22 결과와 플랜, wall 비교가 있습니다. 측정한 결과가 있으면 PR 이나 JIRA 에 붙여 주실 수 있을까요?

## CUBRID/cubrid-testcases#3358 (TC)

- event: COMMENT
- commit_id: 0a6a13ffc6cee26c334b666582eb14317ba13755
- inline: 없음

### top-level body

엔진 PR 에 남긴 것처럼 develop 에 CBRD-27664 TC (`66e5bdbd4`) 가 들어와서 `20158_table_schema2.answer` 를 이미 고쳤습니다. 엔진 sync 뒤의 출력도 그 답과 같습니다. sync 할 때 이 파일은 develop 쪽 답을 쓰면 될 것 같습니다.

본문 Implementation 에는 Case 1~5 만 있는데, 파일에는 파티션 테이블 inner (Case 6) 와 클래스 계층 inner (Case 7) 도 있습니다. 본문에도 같이 적어 두면 어떨까요?

## cubrid-testcases-private-ex#3995

리뷰 없음 (grill Q7).
