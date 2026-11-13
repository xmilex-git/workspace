# PR #6466 post-ready comments

## reply to greptile thread 4451270815 (`src/storage/btree.c`, MRO)

말씀하신 경로가 실제로 실패합니다. `(i, j, sqrt(d))` 인덱스에 2000행을 넣고 돌려 보았습니다.

```sql
select j, sqrt (d) from t where i in (1, 2) order by j limit 5;
```

develop 은 `(multi_range_opt)` 비커버링으로 5행인데, 이 PR 은 `index: idx_t term[0] (covers) (multi_range_opt)` 로 계획되고 `Query execution failure`(JDBC -495)로 끝납니다. `for orderby_num () <= 5` 꼴도 같습니다. `scan_dump_key_into_tuple ()` 가 `btree_attrinfo_read_dbvalues ()` 에 `func_index_col_id` 로 -1 을 넘겨서, 병렬 leaf walker 처럼 `iscan_id->indx_cov.func_index_col_id` 를 넘겨야 하는 것으로 보입니다.

## reply to greptile thread 4451270825 (`src/parser/xasl_generation.c`, non-covering key filter)

비커버링 질의 `select p from t where i = 1 and sqrt (d) > 44`(`(i, j, sqrt(d))` 인덱스)는 develop 과 이 PR 모두 `sargs: term[0]` 로 남고, `select j, sqrt (d) ...` 처럼 커버링일 때만 `filtr: term[0]` 이 됩니다. PR 본문의 "키 필터 식은 커버링 여부와 무관하게" 가 커버링일 때를 말하는 것인지, 비커버링도 이 PR 의 대상인지 궁금합니다.

## CUBRID/cubrid#6466 (engine) — event: REQUEST_CHANGES, commit_id 05b46aefe5253cd48c5f08214634d2b39f37a068

### top-level

MRO 경로 실패를 greptile 스레드에 재현과 함께 답했습니다. 병렬 인덱스 스캔으로 커버링되는 40만 행 질의는 `NO_COVERING_IDX` 와 결과가 같았습니다.

확인 부탁드립니다
- JIRA Implementation 절에 적힌 `pt_get_func_index_cover_arg`, `pt_add_func_index_result_col`, `qo_seg_used_only_in_covering_func_index` 같은 이름이 지금 코드에는 없고, "함수 인자가 일반 키 컬럼으로도 존재하면 라우팅하지 않는다" 는 `74326dd77` 과 반대입니다. 지금 코드에 맞게 고쳐 주시면 좋겠습니다.

## CUBRID/cubrid-testcases#3865 — event: COMMENT, commit_id 059fbce8ec27e351cbcfbe38f3a8af851441c6e2

### inline `sql/_36_guava/cbrd_25984/cases/cbrd_25984.sql:199` (RIGHT)

MRO 를 타는 꼴(`where i in (1, 2) order by j limit 5`, `for orderby_num () <= 5`)이 없어서 엔진 PR 의 MRO 실패를 CI 가 잡지 못했습니다. 엔진 수정과 함께 이 꼴을 `NO_COVERING_IDX` 대조로 넣으면 어떨까요?

## CUBRID/cubrid-testcases-private-ex#4551 — no review (draft)
