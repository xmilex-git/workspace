# PR-8196 post-ready comments

게시 전 사용자 확인 필요. 각 섹션 위의 메타데이터는 게시용이 아니다.

---

## CUBRID/cubrid#8196

- event: REQUEST_CHANGES
- commit_id: 908bdc5af67a752fd168b71cdf2c6f140520861d

### top-level body

develop 빌드(c966fabc6)와 이 PR head(908bdc5af)의 CI 빌드로 같은 질의를 돌려가며 봤습니다. 필터·집계 모양 70여 개(직렬/병렬)와 다른 세션의 미커밋 DML 이 있는 상태의 집계는 develop 과 결과가 같았고, GROUP BY 쪽에서 아래 인라인 코멘트의 문제가 나왔습니다.

확인 부탁드립니다
- 런타임 필터, 잔여분 해시 병합(병렬 병합 포함), 그룹 slab 은 CBRD-27361 본문과 설계 문서에는 없는 내용인 것 같습니다. 본문에 제안하신 리뷰 단위대로 티켓/PR 을 나누실 계획인지 궁금합니다.
- 병렬 GROUP BY trace 에서 `(parallel workers: ...)` 줄과 JSON 의 `PARALLEL GROUPBY` 블록이 빠졌는데(`cbrd_20865`, `hash_agg_query_profile` 답안), 병렬 병합의 워커 수와 시간은 어디서 확인하면 될까요?
- Greptile 코멘트 4건에 아직 답이 없어서 확인 부탁드립니다. 축출 캐시 건은 재현 결과를 해당 스레드에 남겼습니다.

### inline: src/query/query_aggregate.cpp:4182 (RIGHT)

부분 집계 튜플은 키 뒤에 집계마다 value/value2/count 3열과 tuple_count 가 붙는데, 여기서는 열 개수를 `key->val_count` 로 넘겨서 NULL 비트맵이 작게 계산되는 것 같습니다. 열이 33개를 넘으면 키 위치가 어긋나서, 아래 질의가 release 에서는 `Internal system failure`, optdebug 에서는 `qfile_tuple_layout.h:1005` assert 로 서버가 내려갑니다(develop 은 5038건 정상, 집계 10개까지는 head 도 정상). 기존 `qdata_load_agg_hentry_from_tuple ()` 처럼 전체 열 개수(리스트의 `type_list.type_cnt`)를 넘겨야 하지 않나요?
```sql
create table gs5 (k varchar(250), i int);
insert into gs5 with recursive cte(n) as (select 1 union all select n + 1 from cte where n < 1000) select case when mod(rownum, 10) < 7 then 'h' || mod(rownum, 50) else 'c' || mod(rownum, 5003) end, mod(rownum, 1000) from cte a, cte b limit 300000;
select k, count(*), sum(i), sum(i+0), sum(i+1), sum(i+2), sum(i+3), sum(i+4), sum(i+5), sum(i+6), sum(i+7), sum(i+8) from gs5 group by k;
```

### inline: src/query/query_executor.c:19631 (RIGHT)

런타임 필터를 끌 수 있는 파라미터나 힌트가 없는 것 같습니다. CBRD-27361 완료 조건에 hidden 파라미터 on/off 가 있었고, 지금은 `cbrd_25717` 처럼 병렬 해시 조인을 보려는 TC 가 필터 때문에 그 경로를 타지 않게 되어서, hidden 파라미터로 끌 수 있게 하는 것은 어떨까요?

### inline: src/query/scan_manager.c:8254 (RIGHT)

NIT: 서버 코드라 `db_private_alloc` / `free_and_init` 을 쓰는 것이 좋아 보입니다. 이 PR 에서 맨 `malloc`/`calloc`/`realloc` 51곳, 맨 `free` 45곳이 추가된 것 같습니다.

### inline: src/query/expr_batch.h:43 (RIGHT)

NIT: `database-reference 참고:` 주석 8곳이 외부 코드의 심볼(`ColumnBuilder::Build`, `PpNodeUseColumnInfo`, `ExAggr` 등)을 한국어와 섞어 인용하고 있어서, 그 코드를 모르면 읽기 어려운 것 같습니다. 이 코드가 하는 일만 영어로 설명하는 것은 어떨까요?

### inline: src/query/query_executor.c:5782 (RIGHT)

NIT: 초기 크기 `1024` / `1023` 을 이름 있는 상수로 두는 것은 어떨까요?

---

## CUBRID/cubrid#8196 — Greptile 스레드 답글

- target: review comment 4322136746 (`src/query/query_executor.c:11913`), `pulls/8196/comments/4322136746/replies`

재현해 봤습니다. `max_agg_hash_size=64K` 에서 키 길이가 다른 그룹이 한 번에 여러 개 축출되게 만들면, 직렬은 300000건 중 3건이 빠지고 73개 그룹 값이 틀리며 `parallel(4)` 는 41개 그룹이 틀립니다(develop 정상, 키 길이를 고정하면 정상).
```sql
create table ge401 (k varchar(250), i int);
insert into ge401 with recursive cte(n) as (select 1 union all select n + 1 from cte where n < 1000) select case when mod(rownum, 10) < 7 then 'h' || mod(rownum, 50) else 'c' || mod(rownum, 401) || repeat('y', mod(mod(rownum, 401) * 37, 200)) end, mod(rownum, 1000) from cte a, cte b limit 300000;
select k, count(*), sum(i) from ge401 group by k;
```

---

## CUBRID/cubrid-testcases#3791

- event: COMMENT
- commit_id: 20f030b6fed9481f5f1f75563951fde8908111f4

### top-level body

엔진 PR 의 런타임 필터 때문에 병렬 해시 조인을 확인하려던 케이스 몇 개가 그 경로를 타지 않게 된 것 같습니다. 답안에서 `HASHJOIN (... parallel workers: ?)` / `SPLIT` / `PARALLEL` 줄이 빠진 곳은 `cbrd_25717_nm_skew_join` Case 3, `cbrd_25717_empty_input`, `cbrd_25717_during_join_predicates`, `cbrd_27561` 2건입니다. 엔진 쪽에서 필터를 끌 수 있게 되면 이 케이스들은 원래 경로를 유지하도록 맞추는 것이 좋겠습니다.

### inline: sql/_36_guava/cbrd_25717/answers/cbrd_25717_nm_skew_join.answer:113 (RIGHT)

Case 3 은 skew 된 build 쪽을 분할해서 작업 분배를 보려는 케이스인데, 런타임 필터가 `t_sk_uniq` 100000건 중 99599건을 먼저 버려서 SPLIT/PARALLEL 없이 메모리 해시 조인으로 끝나는 것 같습니다(로컬 develop 빌드는 SPLIT 13분할, memory+file). 이 케이스는 필터 없이 원래 경로를 타게 하는 것이 맞지 않을까요?

---

## CUBRID/cubrid-testcases-private-ex#4469

리뷰 없음 (grill Q16).

---

## 게시 기록 (2026-10-21)

- Greptile 스레드 답글: https://github.com/CUBRID/cubrid/pull/8196#discussion_r4335849042
- 엔진 PR 리뷰 (CHANGES_REQUESTED, 인라인 5): https://github.com/CUBRID/cubrid/pull/8196#pullrequestreview-5598484931
- TC PR #3791 리뷰 (COMMENTED, 인라인 1): https://github.com/CUBRID/cubrid-testcases/pull/3791#pullrequestreview-5598485460
