# PR-7658 post-ready comments (grill 2026-10-15 확정, 게시 전)

모든 SQL과 숫자는 gha-ci optdebug tarball(develop `5b1867174`, PR `c0a9d2ff3`)에서 csql -S / csql -C로 확인합니다
(최종 확인: `.git_ignored_dir/scratch/tc-author/CBRD-27215/run11/`).

---

## CUBRID/cubrid#7658 — review event: REQUEST_CHANGES, commit_id c0a9d2ff3d006ad5b1f6ab7b5dc70dd818ff1f18

### top-level

식 컴파일 경로를 develop 과 같은 SQL 로 나란히 돌려 문장 단위로 결과를 비교해 봤습니다. 무작위 식 트리 1,750개를 투영, 필터, CASE 분기, SUM/AVG, GROUP BY, 준비문 재실행 문맥에 넣은 약 1만 2천 문장과, 비결정 함수, 시리얼, 세션 변수, CONNECT BY, LOB, 상관 서브쿼리, DML, 병렬 30만 행 같은 수작업 형태는 develop 과 같았습니다. 다만 준비문 재실행, 필터 값 공유, 집계 피연산자 쪽에서 결과가 달라지는 형태가 나와서 인라인으로 남깁니다. 1~3 은 결과가 틀리거나 서버가 내려가는 경우라 머지 전에 봐 주셨으면 합니다. 인라인의 형태들은 CTP 케이스(sql 6개, 인라인 1 은 shell 케이스)로도 만들어 두었고 develop 에서는 매번 OK, 이 PR head 에서는 NOK 입니다. 필요하시면 tc/pr-7658 에 넣겠습니다.

확인 부탁드립니다
- private-ex #3869 의 `_01_show_table.answer` 가 현재 head 의 `;plan detail` 출력과 맞지 않아 gha-ci shell 에서 NOK 입니다(run 38680302759). 10-13 이후 generic step 줄(`op=T_COALESCE`, `op=T_ADD ... dom=set`)이 추가된 영향으로 보입니다.

### inline 1 — src/query/expr_compile.c:1497 (`expr_k_resolved_value`)

게이트가 계산한 값이 있으면 셀을 `ctx->vd->dbval_ptr + ref` 로 돌려 두는데, 다음 실행에서 `expr_prog_enter_execution ()` 이 셀을 노드 슬롯으로 되돌리지 않는 것 같습니다. 그래서 exec-prologue 로 올라간 스텝(아래는 `? + 1` 을 NUMERIC 으로 바꾸는 coerce)이 이 체크보다 먼저 돌면서 이전 실행의 해제된 값 배열을 읽고, 두 번째 실행부터 NULL 이나 이전 실행의 값이 나옵니다. csql -C 와 CTP shell 케이스(csql)에서 매번 재현되고, csql -S 와 CTP sql(브로커 경유)에서는 같은 SQL 이 맞게 나왔습니다. 해제된 배열 자리를 다음 실행이 다시 받으면 우연히 맞는 것으로 보입니다.
```sql
create table t0 (id int, n numeric(10,2));
insert into t0 values (1, 1.50), (2, 2.25);
prepare st from 'select id, (? + 1) * n from t0 order by id';
execute st using 1;     -- 3.00, 4.50
execute st using 10;    -- develop 16.50, 24.75 / PR 3.00, 4.50
execute st using 100;   -- develop 151.50, 227.25 / PR 16.50, 24.75
execute st using 1000;  -- develop 1501.50, 2252.25 / PR 151.50, 227.25
```
`sum((? + 1) * n)`, `(? + 1) + n`, `? * 2 * n` 도 같았고, 사이에 다른 문장을 끼우면 NULL 이 나오기도 했습니다. 준비문을 재사용하는 흔한 형태라서, 실행마다 이 셀들을 슬롯으로 되돌리거나, 이 체크도 exec-prologue 에서 먼저 돌게 하는 건 어떨까요?

### inline 2 — src/query/expr_compile.c:3188 (`expr_scan_pred_share_build`)

`cast(10 as numeric(10,2))` 처럼 게이트가 실행 전에 계산하는 상수 노드는 필터 프로그램에서 `expr_k_resolved_value` 가 cast 스텝을 건너뛰어서, 여기서 등록하는 슬롯이 채워지지 않는 것 같습니다. 같은 노드를 가진 투영/집계가 이 슬롯을 읽으면 NULL 이 나오고, NVL 은 두 번째 인자를 고릅니다.
```sql
create table t1 (id int, i int, p numeric(10,2));
insert into t1 values (1, 1, 100.00), (2, 2, 50.50), (3, null, 7.25), (4, -4, null), (5, 5, null);
select id, p - cast(10 as numeric(10,2)) from t1 where p > cast(10 as numeric(10,2)) order by id;  -- develop 90.00, 40.50 / PR NULL, NULL
select sum(p - cast(10 as numeric(10,2))) from t1 where p > cast(10 as numeric(10,2));             -- develop 130.50 / PR NULL
select sum(nvl(cast(1 as int), i)) from t1 where nvl(cast(1 as int), i) > 0;                        -- develop 5 / PR 4
```
`to_date('2020-01-01', 'YYYY-MM-DD')`, 날짜 리터럴, `sysdate`, 호스트 변수로 같은 형태를 만들면 develop 과 같았고, 리터럴을 CAST 한 노드에서만 나왔습니다. `resolved_value` 스텝이 publish 하는 셀은 공유 목록에서 빼거나, 게이트 값을 슬롯에도 채워 두는 건 어떨까요?

### inline 3 — src/query/expr_compile.c:1725 (`expr_share_same`)

도메인을 type/precision/scale 로만 비교해서 ENUM 원소 목록, charset, collation 만 다른 CAST 가 같은 식으로 매칭되는 것 같습니다. 투영이 필터 쪽 값을 읽어서 값이 달라지고, collation 이 다르면 optdebug 에서 `db_string_compare` 의 collation assert(`string_opfunc.c:530`)로 서버가 내려갑니다.
```sql
create table t2 (id int, s varchar(10));
insert into t2 values (1, 'a'), (2, 'b');
select id, cast(s as enum('b', 'a')) + 0 from t2 where cast(s as enum('a', 'b')) + 0 > 0 order by id;  -- develop 2, 1 / PR 1, 2
create table t3 (id int, s varchar(20) collate utf8_en_cs, c varchar(20) collate utf8_en_ci);
insert into t3 values (1, 'abc', 'ABC');
select id, strcmp(cast(s as varchar(20) collate utf8_bin), 'ABC') from t3 where cast(s as varchar(20) collate utf8_en_ci) = c;  -- develop 1 / PR: server abort
```
시드를 준 `rand(1)` 처럼 노드마다 상태를 가진 연산자가 들어 있는 식도 같은 값으로 보고 공유합니다(`select id, rand(1) - 1 from t where rand(1) - 1 > a` 의 출력이 develop 은 투영 노드 자신의 수열, PR 은 필터의 값). 도메인은 원소 목록과 codeset, collation 까지 비교하고, `expr_arith_side_effect ()` 에 걸리는 연산자가 들어 있는 서브트리는 공유하지 않는 게 맞지 않을까요?

### inline 4 — src/query/query_aggregate.cpp:1263 (`qdata_evaluate_aggregate_list`)

프로그램이 덮는 집계 피연산자를 집계 루프 전에 한꺼번에 평가해서, GROUP_CONCAT 처럼 프로그램 밖 집계의 피연산자와 부수효과 순서가 develop(집계 리스트 순서, 즉 SELECT 목록의 역순)과 달라집니다.
```sql
create table t6 (i int);
insert into t6 values (1), (2), (3);
create serial s6;
select max(s6.next_value * 1), group_concat(s6.next_value) from t6;  -- develop 6, '1,3,5' / PR 5, '2,4,6'
set @a = 0;
select max(@a := @a * 2), group_concat(@a := @a + 1) from t6;        -- develop 14, '1,3,7' / PR 6, '1,3,7'
```
SELECT 목록 안의 평가 순서는 SQL 이 정하지 않으니 막을 일은 아니라고 생각합니다. 다만 투영 리스트는 bug_bts_9234 때 부수효과가 있으면 해석 경로로 두는 규칙을 넣으셨으니, 집계 리스트도 프로그램 밖 집계의 피연산자까지 보도록 맞추거나, 바뀌는 것으로 두신다면 JIRA spec 에 적어 두시면 좋을 것 같습니다.

### inline 5 — src/query/expr_compile.c:4166 (`'^'` 규칙)

해석 경로는 WIDTH_BUCKET 을 왼쪽 -> 두 경계 -> bucket 수 순서로 fetch 하는데, 여기서는 bucket 수를 경계보다 먼저 스텝으로 계산해서 오류 우선순위와 시리얼 소비 순서가 달라집니다.
```sql
create table t7 (a int, lo int, z int, n varchar(10));
insert into t7 values (5, 10, 0, 'x');
select width_bucket(a, lo / z, 100, cast(n as int)) from t7;  -- develop: divide by zero / PR: cannot coerce
create serial s7;
select width_bucket(60, s7.next_value, s7.next_value + 100, mod(s7.next_value, 7) + 1) from t7;  -- develop 3 / PR 2
```
bucket 수도 경계 다음에 `expr_k_generic ()` 안에서 fetch 하면 어떨까요?

### inline 6 — src/query/query_aggregate.cpp:1126 (`word_operand`)

develop 은 SUM/AVG 의 DOUBLE 트리도 `REGU_VARIABLE_AGG_OPERAND` 로 fused 경로(`fetch_agg_expr_eval_dbl`)에서 계산하는데, 여기서는 NUMERIC 트리와 CAST_WRAP 만 남기고 DOUBLE 나눗셈은 generic step 으로 가서 `qdata_is_divided_zero ()` 의 `DBL_EPSILON` 판정을 받습니다.
```sql
create table t9 (d double, x double);
insert into t9 values (1.0, 1e-20), (2.0, -1e-20), (3.0, 1e-17);
select sum(d / x), avg(d / x) from t9;  -- develop -9.97e+19, -3.32e+19 / PR: divide by zero
```
develop 의 투영(`select d / x from t9`)도 같은 오류를 내서 develop 쪽이 일관되지 않은 면은 있지만, 기존에 값이 나오던 집계가 오류로 바뀌는 것이라 `REGU_VARIABLE_AGG_OPERAND` 가 붙은 피연산자는 NUMERIC 처럼 fused 경로에 두는 게 안전해 보입니다.

### inline 7 (질문) — src/query/numeric_opfunc.c:4372

CBRD-27408 포트로 41자리에 이른 합을 `+` 처럼 반올림하게 되면서 결과가 더하는 순서를 따르게 됐는데, 병렬 스캔은 워커 부분합을 `numeric_sum_acc_merge ()` 로 합치니 직렬과 값이 달라지는 것 같습니다.
```sql
create table t10 (n numeric(38,30));
insert into t10 select 99999999.999999999999999999999999999999 from db_class a, db_class b, db_class c limit 60000;
insert into t10 select -99999999.999999999999999999999999999999 from db_class a, db_class b, db_class c limit 60000;
select /*+ parallel(0) */ sum(n) from t10;  -- develop 0.000000000000000000000000000000 / PR 0.000000000000000000000000000100
select /*+ parallel(4) */ sum(n) from t10;  -- develop 0.000000000000000000000000000000 / PR 0.000000000000000000000000000
```
직렬의 잔차는 CBRD-27408 의 의도("40자리 초과 SUM = + 체인")로 이해했는데, 병렬에서는 그 체인이 성립하지 않고 스케일까지 바뀝니다. csql -C 결과이고, parallel(2), parallel(8) 도 parallel(4) 와 같았습니다. 병렬 결과가 직렬과 달라도 되는 것으로 보신 건지 궁금합니다.

### inline 8 (질문) — src/query/query_opfunc.c:440 (`eval_prog_row_ready`)

SET 컬럼이나 페이지를 넘는 행처럼 튜플을 다시 만드는 경우 develop 은 리스트를 두 번 평가해서 시리얼을 두 번 뽑는데, 이 PR 은 한 번만 뽑습니다. develop 쪽이 오히려 이상한 동작으로 보이긴 하는데, 결과가 달라지는 부분이라 의도하신 것이면 본문에 적어 두시면 좋겠습니다.
```sql
create serial s11 start with 1 nocache;
create table t11 (id int, st set(int));
insert into t11 values (1, {1,2}), (2, {3}), (3, {4,5});
select id, s11.next_value, st from t11 order by id;  -- develop 2, 4, 6 / PR 1, 2, 3
```

---

## CUBRID/cubrid-testcases-private-ex#3869 — review event: COMMENT, commit_id f28b9538760864fab1c803f87f8669539cd0b20d

### top-level

`_01_show_table.answer` 가 현재 엔진 head(`c0a9d2ff3`)의 `;plan detail` 출력과 맞지 않아 gha-ci shell 에서 NOK 입니다(run 38680302759 shard 38). 10-13 이후 generic step 줄이 EXPR_COMPILE 절에 추가된 영향으로 보여서, 이 head 기준으로 답안을 다시 만들어 주시면 될 것 같습니다.

## CUBRID/cubrid-testcases#3239

develop 대비 바뀐 파일이 없어 리뷰를 남기지 않습니다.
