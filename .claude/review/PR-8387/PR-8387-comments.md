# PR-8387 post-ready comments

## CUBRID/cubrid#8387 (engine)

- event: APPROVE
- commit_id: 7c76a0af734e4a67beb1f3750034ae8cbd02688c

### top-level body

NL ANTI JOIN 에서 `after_join_pred`, `if_pred` 를 짝 판정에서 빼고 짝이 없는 바깥 행에서 평가하도록 바꾼 흐름 확인했습니다. merge-base(4e389935d) optdebug 빌드에서는 JIRA 재현 (1) 이 1 row, (2) 와 명시적 ANTI JOIN 이 2 로 나오고, 이 PR 빌드에서는 0 rows, 0, 0 으로 나옵니다. LEFT OUTER inner 의 `t2.c2 IS NULL` 단독 조건도 merge-base 에서는 1, 3, 4, 5 이고 이 PR 에서는 `USE_HASH` 와 같은 5 입니다.

memoize 키 관련해서 하나 제안드립니다. memoize key maker(`memoize.cpp` 의 `if_pred`, `after_join_pred` 를 키에 넣는 부분)는 그대로라서, ANTI inner 에서는 이제 짝 판정에 쓰이지 않는 WHERE 조건의 바깥 컬럼까지 키에 들어갑니다. 그래서 WHERE 조건이 LEFT OUTER inner 컬럼을 읽으면 키가 그 값만큼 늘어나 inner 를 다시 읽습니다.

```sql
-- t6 200행 (c1 = 1..4), t2 40행 (c1 = 1..4, c2 = 1..40), t3 (1, 2), (2, 9)
select /*+ recompile use_nl */ count (*) from t6 left outer join t2 on t2.c1 = t6.c1
 where not exists (select 1 from t3 where t3.c1 = t6.c1) and (t2.c2 > 0 or t6.c1 is null);
-- t3 MEMOIZE hit 1960, miss 40, t3 readrows 70  (WHERE 조건을 빼면 miss 4, readrows 7)
```

`XASL_NL_ANTIJOIN` inner 에서는 key maker 와 `nondeterministic_check` 가 두 술어를 건너뛰게 하는 것은 어떨까요? develop 도 같은 키를 쓰고 있어서 이 PR 로 느려지는 것은 아니고, 이 PR 덕분에 줄일 수 있게 된 부분입니다.

### inline

1. `src/query/query_executor.c` line 11757 (RIGHT)

NIT: `after_join_pred` 블록과 `if_pred` 블록이 술어만 다르고 같은 내용이라, 두 술어를 배열로 돌며 한 블록으로 합쳐도 좋아 보입니다.

## CUBRID/cubrid-testcases#4008 (TC)

- event: APPROVE
- commit_id: 4b46c011e76a022cab1c8d2a50b335faa8ecc028

### top-level body

Case 1-5 기대값을 데이터에서 다시 계산해 보니 answer 와 같습니다. merge-base(4e389935d) optdebug 빌드에서는 Case 1-4 에서 2, 4 행이 더 나와 NOK 이고, PR head CI 에서는 OK 입니다.

지금 케이스는 모두 LEFT OUTER JOIN 에 OR 조건을 붙인 형태라, 아래 세 형태도 추가하는 것은 어떨까요? JIRA 재현 (1) 의 RIGHT OUTER JOIN + `IS NULL`, 명시적 `ANTI JOIN ... WHERE`, 그리고 LEFT OUTER inner 컬럼의 `IS NULL` 단독 조건입니다. 마지막 형태는 지금 데이터의 t1 에 (5) 를 더하면 merge-base 에서 1, 3, 4, 5 가 나오고(정답 5) 오답 폭이 가장 큽니다.

```sql
select t1.c1, t2.c2 from t1 left outer join t2 on t2.c1 = t1.c1
 where not exists (select 1 from t3 where t3.c1 = t1.c1) and t2.c2 is null order by 1;
```

## CUBRID/cubrid-testcases-private-ex#4711

리뷰 없음 (변경 파일 없는 draft).
