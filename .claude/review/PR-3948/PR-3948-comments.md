# PR #3948 / #4648 comments

## CUBRID/cubrid-testcases#3948

Event: Approve (commit cb622267c239632cd305814f965e75a762732a00)

Top-level:

develop TC와 비교해 answer는 trace 줄만 바뀌었고 행 값은 같습니다. 11.4.6.1963 release에서는 cbrd_27759가 Case 1에서 크래시하고 cbrd_27759_chain은 Case 1에서 row 2를 빠뜨립니다. 52d4301 release 빌드에서는 두 케이스 모두 OK입니다. Case 12 주석 한 곳만 의견 남겼습니다.

Inline `sql/_13_issues/_26_2h/cases/cbrd_27759.sql:108` (RIGHT):

11.4에서도 CTE 참조 spec은 `pt_resolve_spec_to_cte()`에서 `entity_name`이 NULL이 되어서, Case 12의 `rhs s`도 backport된 `qo_reduce_outer_joined_tables()`의 `!PT_SPEC_IS_ENTITY (spec)` 검사에서 Case 11과 똑같이 돌아갑니다. 그래서 Case 12도 develop 헤더의 "CTE right input preserves duplicate matches"를 그대로 확인합니다. trace가 다른 이유를 적은 첫 줄만 남기고 이 줄은 빼는 건 어떨까요?

## CUBRID/cubrid-testcases-private-ex#4648

Event: Approve (commit 7784bc5af7110fd0444083909bcf9ac12b16074f)

Top-level:

한도값과 적재 순서, probe 인자만 바뀌었고 판정은 develop과 같은 의미입니다. 52d4301 release 빌드에서 세 케이스 모두 OK였고, create는 640 pages 에러에 file_hash_readrows=0, limit은 896 pages 에러에 file_hash_readrows=126380으로 의도한 시점에서 멈췄습니다.
