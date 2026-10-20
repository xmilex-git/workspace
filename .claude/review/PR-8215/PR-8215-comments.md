# PR #8215 post-ready comments

## CUBRID/cubrid#8215 (engine)

- event: APPROVE
- commit_id: 5805911552e8017d6704a12d0625a567b008a6bd
- inline comments: 없음

top-level body:

이슈 repro 기준으로 확인했습니다. develop merge-base(423e57f2c)와 이 PR head(5805911)를 optdebug로 빌드해 SA/CS 모두 돌려 보았고, merge-base에서 `NULL, 25` / `25, 35`로 나오던 결과가 head에서 `1, 25` / `1, 35`로 나옵니다. 컬럼 값이 모두 NULL인 파티션, DATETIMELTZ와 VARCHAR(utf8_en_ci) 컬럼, list 파티션, DESC 인덱스, 첫 컬럼이 NULL인 키만 있는 복합 인덱스, 삭제된 키만 남은 파티션에서도 head 결과가 전체 스캔 결과와 같았습니다. 파티션 테이블에 WHERE 없는 MIN/MAX가 있는 기존 sql TC 11개 디렉터리(728건)도 merge-base와 head 모두 통과했습니다.

## CUBRID/cubrid-testcases#3813, CUBRID/cubrid-testcases-private-ex#4498 (TC)

리뷰 없음 (둘 다 변경 없는 빈 draft, grill Q12).
