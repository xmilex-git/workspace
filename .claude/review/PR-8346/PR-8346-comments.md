# PR-8346 post-ready comments

## CUBRID/cubrid#8346 (engine)

- review event: Approve
- commit_id: 080aff3cd1d2c3f403fe75941170b59624c71db7

### top-level

조인 + GROUP BY LIMIT에서 바깥 인덱스 순서로 정렬 없이 집계하고 그룹 한도에서 조인을 멈추는 변경 확인했습니다. head debug 빌드 CI(sql/medium/shell)와 별도로 RIGHT JOIN, 파생 테이블과 CTE 안쪽, self join, 범위 조인 조건, EXISTS, 3개 테이블 조인을 skip 플랜으로 돌려 USE_HASH 결과와 비교했고 모두 같았습니다.

### inline: src/optimizer/query_planner.c:438 (RIGHT)

NIT: 새 static 선언 8개가 `qo_plan_is_orderby_skip_candidate`와 `qo_is_sort_limit` 사이에 모여 있는데, 정의는 `qo_check_groupby_iscan`이 `qo_walk_plan_tree` 뒤, `qo_groupby_limit_groups`부터 `qo_plan_is_groupby_limit_join`까지가 `qo_can_apply_limit_card` 뒤, 나머지 둘이 `qo_find_best_parallel_driving_plan_on_info` 뒤에 있습니다. 선언도 정의 순서에 맞춰 옮기는 건 어떨까요?

## CUBRID/cubrid-testcases#3961 (sql TC)

- review event: Approve
- commit_id: 35904792c2723f830ef38e6453e5b4f0e847b011
- body: 없음

## CUBRID/cubrid-testcases-private-ex#4672 (shell TC)

- review event: Approve
- commit_id: 33317ed9154241d2210a175acb70dd38a2946b05
- body: 없음
