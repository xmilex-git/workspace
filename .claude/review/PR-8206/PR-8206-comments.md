# PR #8206 게시용 리뷰 코멘트

## CUBRID/cubrid#8206

- event: APPROVE
- commit_id: 8cbdf888a2ce80622a1f4bae1957e936b66921f0

### top-level body

`orderby_desc` / `groupby_desc`는 `scan_get_index_oidset`에서 `orderby_skip` / `groupby_skip`과 함께일 때만 쓰이는 것으로 확인했습니다. 그래서 checker에서 desc 조건을 빼도 정렬 생략 스캔은 그대로 직렬로 남는 것 같습니다. develop과 수정본에 TC를 돌려 보니 Q1/Q3/Q4만 직렬에서 병렬로 바뀌었고, 결과 행은 같았습니다.

## CUBRID/cubrid-testcases#3800

- event: APPROVE
- commit_id: 445163301b3fdb906ff31472ce9e5f925dde82eb

### top-level body

(없음)

### inline 1: `sql/_36_guava/cbrd_27689/cases/cbrd_27689.sql:41` (RIGHT)

이 범위는 행이 15개뿐이라, 정렬 생략과 상관없이 옵티마이저의 선택도 기준(`qo_apply_parallel_index_scan_threshold`)에서 이미 직렬이 되는 것으로 보입니다. 같은 범위에 정렬 생략이 아닌 `order by v desc, name`도 직렬로 나왔습니다. 그래서 checker의 skip 조건이 빠져도 이 케이스는 통과할 것 같습니다. `PARALLEL(4)` 힌트를 붙이면 선택도 기준을 건너뛰기 때문에 skip 조건만 남는데, 이렇게 바꾸는 건 어떨까요? 수정본에서는 직렬 + `skip order by: true`이고 결과 순서도 같았습니다.
```suggestion
select /*+ recompile PARALLEL(4) */ name from t_27689 where name > 'Char049995' order by name desc;
```

### inline 2: `sql/_36_guava/cbrd_27689/cases/cbrd_27689.sql:45` (RIGHT)

Q5와 같은 이유로 `PARALLEL(4)`를 붙이는 건 어떨까요? 수정본에서 직렬 + `group by nosort: true`이고 결과도 같았습니다.
```suggestion
select /*+ recompile PARALLEL(4) */ name, count (*) from t_27689 where name > 'Char049998' group by name desc;
```

## CUBRID/cubrid-testcases-private-ex#4481

리뷰 없음 (파일 변경 없는 빈 draft).

## 기존 스레드

- greptile의 #3800 요약(Q1/Q2 집계값이 모두 3000)은 다시 올리지 않는다.
