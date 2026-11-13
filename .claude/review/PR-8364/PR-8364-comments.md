# PR #8364 post-ready comments

## CUBRID/cubrid#8364 (engine) — event: REQUEST_CHANGES, commit_id 7d09a54cb71f1870e6cb293145c105d35edf849c

### top-level

`bfc323a9a` 이후 debug CI 에서 TC Case 8 이 서버 core 로 끝나고 있습니다(run 41623402810, 41770625665 두 번 모두 `expr_agg_prog_settle` assert). 아래 inline 에 원인과 고칠 자리를 적었습니다.

### inline `src/query/query_executor.c:14266` (RIGHT)

클라이언트는 직렬화 때 `xts_save_agg_prog_image ()` 에서 `agg_optimized` 인 집계를 빼고 operand 이미지를 씁니다(`expr_agg_roots ()` 의 `participates = !agg_p->flag.agg_optimized && ...`). 그런데 여기서 서버가 `agg_optimized` 를 지우고 행 루프를 돌면, `expr_agg_prog_settle ()` 가 다시 컴파일한 프로그램에는 그 집계가 들어가서 이미지와 달라집니다.

```sql
create table t_po8 (g int, c varchar(10), n int);
create index i_t_po8_g on t_po8 (g);
insert into t_po8 values (1, 'h1', 1), (2, 'h2', 2), (3, 'h3', 3);
update statistics on t_po8 with fullscan;
select min(s.g), (select max(s.c)) from t_po8 s;
```

debug 빌드 : `Assertion 'expr_image_same_prog (prog, here)' failed` 로 서버가 죽습니다(Case 8 의 ODKU 문장도 같음) / release 빌드: `1, 'h3'`. develop debug 는 assert 없이 NULL 입니다. CONNECT BY 는 `pt_to_aggregate ()` 가 처음부터 `flag_agg_optimize` 를 켜지 않아서 같은 분기를 타도 괜찮은 것으로 보입니다. `pt_to_buildvalue_proc ()` 에서 `XASL_OUTPUT_READS_SCAN` 을 세울 때 `agg_list` 의 `agg_optimized` 를 같이 내리면 이미지와 서버가 같은 집계를 컴파일하고 이 분기도 필요 없어지는데, 어떨까요?

### inline `src/query/xasl.h:596` (RIGHT)

열려 있는 #8056 의 `XASL_PASS_THROUGH_WRAPPER` 도 `0x1 << 29` 를 씁니다. 뒤에 머지되는 쪽이 `0x1 << 30` 으로 옮겨야 할 것 같은데, 어느 쪽이 옮길지 맞춰 두면 어떨까요?

## CUBRID/cubrid-testcases#3985 — no review

엔진 수정 뒤 Case 8 이 debug 에서 통과하는지 다시 본다. 본문의 "debug 에서도 통과" 와 머리 주석 `;` 는 올리지 않음(grill Q3).

## CUBRID/cubrid-testcases-private-ex#4695 — event: APPROVE, commit_id c7ac1b4cfdb5492c248d124b87c4d9ade92aad51

### top-level

칸 13 을 원래 형태로 되돌린 3줄 확인했습니다. run 41770625665 shell 에서 `cbrd_27336_forms` 가 OK 입니다.
