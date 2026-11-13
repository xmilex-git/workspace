# PR #8309 post-ready comments

## CUBRID/cubrid#8309 (engine)

- event: APPROVE
- commit_id: 60f29f5f8f429a641e7105722af6311f30760fe6

### top-level

서브쿼리 FROM 이 여러 테이블일 때 비상관 파생 테이블로 감싸 SEMI / ANTI JOIN 의 inner 로 두는 변환을 확인했습니다. PR 빌드(optdebug)에서 3 테이블, 뷰, 파티션, CTE, collation 이 다른 IN, PREPARE host 변수, INSERT SELECT / UPDATE / DELETE 안의 서브쿼리 등 42개 형태를 돌렸고, 모두 `/*+ NO_UNNEST */` 대조와 결과가 같았습니다. 바깥과 안쪽이 각각 2만 행일 때는 파생 테이블과 hash join 으로 묶여 0.047초에 끝났고, 중첩 실행은 1.506초 걸렸습니다.

확인 부탁드립니다
- CBRD-27376 에 첨부된 design.md 가 CBRD-27774 (분석함수 NULL 파티션) 문서로 보입니다. 이 이슈의 설계 문서로 바꿔 주실 수 있을까요?

### inline: src/optimizer/rewriter/query_rewrite_subquery.c:190 (RIGHT)

USING INDEX 검사는 단일 테이블 분기 안으로 옮겨져 파생 테이블이 힌트를 그대로 갖고 가는데, 바로 위 `QO_UNNEST_QUERY_WIDE_HINTS` 검사는 파생 경로에도 그대로 걸립니다. 그래서 `EXISTS (SELECT /*+ NO_COVERING_IDX */ 1 FROM tb, tc WHERE tb.ca = ta.cb AND tb.cb = tc.ca)` 는 중첩 실행으로 남고, `/*+ ORDERED */` 로 바꾸면 변환됩니다. 파생 경로에서는 이 힌트도 바깥으로 나가지 않으니, 이 검사도 `inner_spec->next == NULL` 분기 안으로 옮기는 것은 어떨까요?

## CUBRID/cubrid-testcases#3916 (TC)

- event: APPROVE
- commit_id: e29aa20d4f22801931cf67b8510bce9d5097acc0
- body: (없음)

## CUBRID/cubrid-testcases-private-ex#4602

- 리뷰 없음 (변경 없는 빈 draft)
