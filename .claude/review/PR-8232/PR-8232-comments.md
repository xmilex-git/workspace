# PR-8232 post-ready comments

## CUBRID/cubrid#8232 (engine)

- event: APPROVE
- commit_id: c9e05bf9121879d92e1ed1a1b40b3b48e2e6e0c6
- inline: 없음

### top-level body

`qo_fold_is_and_not_null` 에서 NULL 피연산자에도 참일 수 있는 형제 항을 근거로 쓰지 않도록 한 부분과, `pt_fold_const_expr` 에서 `NULL <한정 비교> (서브쿼리)` 를 실행 시점으로 넘긴 부분 모두 확인했습니다. develop 과 이 PR 의 CI 빌드로 JIRA Repro 1, 2 와 select 목록, DELETE, 인덱스가 있는 경우, 외부 조인 열에 `IS NULL` / `IS NOT NULL` 이 함께 걸린 경우까지 비교해 봤는데 develop 에서 틀리던 결과가 모두 기대값으로 나오고, 비지 않은 서브쿼리나 호스트 변수처럼 원래 맞던 경우는 그대로인 것 같습니다. TC 쪽에 케이스 하나 추가 제안을 남겼습니다.

## CUBRID/cubrid-testcases#3831 (TC)

- event: APPROVE
- commit_id: 35ad4cc97133a956150e6b04aefbdcde34710f22
- inline 1: `sql/_36_guava/cbrd_27574/cases/cbrd_27574.sql` line 65, side RIGHT

### inline 1 body

`qo_fold_is_and_not_null` 수정은 외부 조인이 NULL 로 채운 열에도 걸리는데, 위 두 LEFT JOIN 질의에는 `IS NULL` / `IS NOT NULL` 이 없어서 이 경로를 타지 않는 것 같습니다. 아래 두 줄을 같이 넣어 두면 어떨까요? develop 에서는 각각 0행, 1, 2, 3 이 나오고 이 PR 에서는 1, 3 과 2 가 나왔습니다.
```sql
select t_27574_a.a from t_27574_a left join t_27574_x x on x.a = t_27574_a.a where x.b is null and x.b not in (select b from t_27574_e) order by 1;
select t_27574_a.a from t_27574_a left join t_27574_x x on x.a = t_27574_a.a where x.b is not null and x.b not in (select b from t_27574_e) order by 1;
```

### top-level body

새 케이스 답지를 질의마다 확인했고, `bug_bts_6526` 답지 갱신도 서브쿼리가 빈 집합이라 맞는 것 같습니다.

## CUBRID/cubrid-testcases-private-ex#4520

변경 없는 draft 라 리뷰하지 않습니다.
