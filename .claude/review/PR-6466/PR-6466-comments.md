# PR #6466 post-ready comments (3차, 2026-11-06)

1차 코멘트는 `PR-6466-r1-comments.md`.

## CUBRID/cubrid#6466 (engine) — event: COMMENT, commit_id f1f4f21ea72fe42f593f0e46aea9d5d1a1bd669f

### top-level

MRO 경로 수정(d7ce3af72)과 이후 커밋들을 f1f4f21ea 로 다시 확인했습니다. 1차에 남긴 `IN` + `ORDER BY ... LIMIT` 질의는 develop 과 같은 5행을 냅니다. 커버링이 아닌 스캔의 함수식 키 필터는 300행 테이블에서 질의 14쌍이 `using index none` 과 같은 행을 냈고, 다른 세션이 스냅샷 뒤에 행을 UPDATE 하고 커밋하거나 롤백하는 경우와 그 뒤 vacuum 까지 develop 과 같은 결과였습니다. 인자 컬럼의 타입 변경(`alter table ... modify`) 뒤에도 인덱스가 `sqrt(cast(d as double))` 로 다시 만들어지고 결과는 develop 과 같았습니다.

남은 것은 아래 inline 하나입니다.

### inline `src/optimizer/query_graph.c:7623` (RIGHT)

키에는 비교해서 같은 값들 중 먼저 들어온 행의 값 하나만 남는데, DOUBLE 은 `-0.0` 과 `0.0` 이 같다고 비교됩니다. 그래서 `ceil`·`round`·`trunc` 처럼 -1 과 0 사이 음수에서 `-0` 을 내는 함수 인덱스는 이 관문을 지나고, 다른 행의 부호를 돌려줍니다.

```sql
create table t (i int, d double);
create index ix on t (i, ceil(d));
insert into t values (1, -0.5), (1, 0);
select i, cast(ceil(d) as varchar(30)) from t where i = 1;
select count(*) from (select i from t where i = 1 and cast(ceil(d) as varchar(30)) = '0') x;
select /*+ NO_COVERING_IDX */ i from t where i = 1 and cast(ceil(d) as varchar(30)) like '-%';
```

develop 은 `'-0'`, `'0'` / 1 / 1행이고, 이 PR 은 debug·release 빌드 모두 `'-0'`, `'-0'` / 0 / 2행입니다. 셋째는 커버링이 아니어도 키 필터가 키 값을 읽어서 달라집니다. develop 의 일반 컬럼 `(i, d)` 커버링도 같은 합침이 있지만, 함수 결과에서는 보통 데이터로 생깁니다. FLOAT/DOUBLE 을 통째로 빼면 `sqrt` 이득이 사라지니, `-0` 을 낼 수 있는 함수만 빼는 쪽과 Remarks 에 적는 쪽 중 어느 쪽으로 생각하시나요?

## CUBRID/cubrid-testcases#3865 — event: REQUEST_CHANGES, commit_id 7763f943db7e3f3394a7e480856189dd4fea81c7

### top-level

엔진 f1f4f21ea(debug 빌드)로 이 브랜치의 변경 디렉터리 8개를 돌리면 기존 답안 8건이 플랜 줄만 달라 실패합니다. 커버링이 아닌 함수 인덱스 스캔에 키 필터를 허용한 0cb8b988a 때문에 `sargs` 가 `filtr` 로 바뀐 것이고, 결과 행은 모두 같았습니다.

- `_13_issues/_12_2h/bug_bts_7088`
- `_13_issues/_24_1h/cbrd_25164`
- `_13_issues/_24_2h/cbrd_24795` (`key filter:` 추가)
- `_36_guava/cbrd_26266`
- `_23_apricot_qa/_02_performance/_02_function_based_index/function_based_index_select_basic_group`
- `.../function_based_index_select_basic_join_003`
- `.../function_based_index_select_basic_order`
- `.../function_based_index_select_basic_where`

이 중 `function_based_index_select_basic_order` 는 고르는 인덱스도 `i_t?_a` 에서 `i_t?_g` 로 바뀌는데, 의도하신 변화인지 궁금합니다. 엔진 PR 본문의 "기존 답안 9건" 도 함께 고쳐 주시면 좋겠습니다. 엔진 쪽 signed zero 코멘트를 고치시면 그 SQL 도 `cbrd_25984` 에 `NO_COVERING_IDX` 대조로 넣으면 어떨까요?

## CUBRID/cubrid-testcases-private-ex#4551 — 리뷰 없음 (11-05 Approve 유지)

## 기존 스레드

- soheejung-cs 4476238590, 4476238835: 작성자와 리뷰어 사이 스레드라 답글을 달지 않습니다.
