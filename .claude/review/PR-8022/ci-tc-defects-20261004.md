# gha-ci 에서 확인한 TC 결함 4건 (2026-10-04)

PR 8022 의 gha-ci 실패를 원인별로 가른 결과, 엔진 결함 1건(CBRD-27557)을 제외한 4건은 테스트케이스 쪽 결함이다. 모두 develop 빌드로 확인했다.

- 증거 출처: gha-ci 아티팩트 `http://192.168.1.48:30080/runs/<run>/<suite>/collect/failed.list`, 2026-09-30 09:08 ~ 2026-10-04 01:38 KST 의 run 120개(`sql`/`shell` 모두). run 의 `headBranch` 는 전부 `develop` 이고 PR run 은 `issue_comment` 트리거다.
- develop 빌드 A/B: gha-ci 가 보관한 develop OptDebug 빌드 `35a7cddb6`(11.5.0.2624, #7866 직전)과 `453da49c8`(11.5.0.2625, #7866 CBRD-27365)로 cbrd_25717 의 sql 14건과 shell 2건을 각각 실행했다. 테스트케이스는 cubrid-testcases develop `dbac2f953`, cubrid-testcases-private-ex develop `9e9f773d1`.
- develop 자체 run: `37016878105`(dispatch sql, 15e7dc8b5), `37027696235`(dispatch all, 15e7dc8b5).

| # | 케이스 | 결함 요지 | develop 증거 |
|---|---|---|---|
| 1 | `sql/_36_guava/cbrd_25717` 9건 + `shell/_40_guava/cbrd_25717/cbrd_25717_membuf_config` 1번 검사 | 답지와 데이터 크기가 #7866 이전의 임시 튜플 크기를 전제 | A/B: 35a7cddb6 전부 통과, 453da49c8 전부 실패. 10-02 이후 sql 을 돌린 13개 run 전부 실패 |
| 2 | `shell/_40_guava/cbrd_25717/cbrd_25717_parallel_degree` 2번 검사 | 상한 기대식 `MIN(32, nproc)` 가 엔진 규칙과 다름 | A/B 두 빌드 모두 25 (기대 32). 10-02 이후 shell 을 돌린 12개 run 전부 실패(CI 는 8) |
| 3 | `sql/_18_index_enhancement_qa/_02_full_test/_06_optimizing_limit/_01_no_data_filter.sql` | ORDER BY 없는 `limit 2,8` 서브쿼리가 힙 순서에 의존 | 120 run 중 1회(37168626427). develop 빌드 실패 증거는 없고, 플랜과 diff 형태로 판단 |
| 4 | `shell/_06_issues/_14_1h/bug_bts_13242` | 잠금 개수만으로 덤프 시점을 맞춰 잠금 집합이 어긋남 | 120 run 중 9 run, 서로 다른 PR 8개 |

## 1. cbrd_25717 답지·데이터 크기 — #7866(CBRD-27365) 이후 어긋남

### 증상

sql 9건의 `show trace` 가 답지와 다르다.

- `agg_inline_view_parallel`, `empty_input`, `multi_hashjoin`, `nm_skew_join`, `null_join_key`, `parallel_hint`, `sector_dependent_list`, `trace_json`: `BUILD (... method: hybrid)` 가 `method: memory` 로 (JSON 은 `"method"` 키). `agg_inline_view_parallel` 은 `memory+hybrid` 도 한 곳.
- `nl_baseline`: HASHJOIN 의 BUILD 와 PROBE 에 오는 테이블이 서로 바뀜 (`t_nla`/`t_nlb`).

shell `cbrd_25717_membuf_config` 의 1번 검사(membuf-only, 500행 입력, `max_hash_list_scan_size=4k`, `parallel(8)`)에서 병렬 해시 조인이 걸리지 않는다(`workers=none`). 결과 500 은 맞다.

### 증거

- A/B: `35a7cddb6` 는 sql 14/14 통과, membuf-only `workers=2`. `453da49c8` 는 sql 9 NOK(위 9건), membuf-only `workers=none`. 두 빌드 사이의 커밋은 #7866 하나다.
- gha-ci: 10-02 이후 sql 을 돌린 run 전부 같은 9건 — 36982998447(PR 7977), 36988875347(PR 8088), 37016878105(develop dispatch), 37027696235(develop dispatch), 37034114694(PR 8090), 37083582591(PR 8088), 37104459999(PR 8022), 37123636959(PR 8091), 37123667615(PR 8092), 37160441993(PR 8093), 37167256858(PR 7985), 37168626427(PR 8022). shell 의 membuf_config 는 shell 을 돌린 run 전부(37016878105 제외)에서 실패.
- 답지는 TC PR 본문대로 `11.5.0.2565-b319ce1`(2026-09-11)에서 생성됐고, TC PR cubrid-testcases#3497 과 private-ex#4150 은 CI 체크 없이 2026-10-02 에 머지됐다.

### 원인

#7866 이 임시 리스트의 튜플 포맷을 줄여 같은 데이터의 리스트 페이지 수와 메모리 추정치가 작아졌다.

- `method: hybrid` → `memory`: 해시 빌드는 입력 리스트가 `max_hash_list_scan_size`(케이스는 256k) 안에 들어가면 메모리 방식을 고른다. 100000행 입력이 이제 그 안에 들어간다.
- `nl_baseline` 의 BUILD/PROBE 교체: 빌드 쪽은 실행 시점에 `tuple_cnt` 가 작은 리스트, 같으면 `page_cnt` 가 작은 리스트로 고른다. 두 테이블이 각 2000행으로 같아 페이지 수가 결정하는데, 포맷이 바뀌며 두 리스트의 페이지 수 관계가 바뀌었다.
- membuf-only 직렬: 병렬 해시 조인은 `parallel_hash_join_page_threshold=0` 이어도 입력이 2페이지 미만이면 직렬로 돈다(하한 2). 500행 (int,int) 리스트가 #7866 이후 1페이지가 됐다.

의도된 엔진 변경이 TC 의 크기 전제를 깬 것이므로 엔진 수정 대상이 아니다.

### 수정 제안

- 답지만 다시 뜨면 "hybrid 방식/파티션을 거치는 경로" 를 검증하려던 의도가 사라진다. 입력 행 수를 늘리거나 `max_hash_list_scan_size` 를 더 낮춰 의도한 방식이 다시 선택되게 한 뒤 답지를 생성하는 쪽이 맞다.
- `nl_baseline` 은 두 테이블의 행 수(또는 폭)를 다르게 해 빌드 쪽이 크기로 정해지게 하거나, 빌드 쪽 고정이 목적이 아니면 trace 에서 테이블 이름이 갈리지 않는 형태로 비교한다.
- membuf-only 는 20페이지 버퍼 안에 들어가되 2페이지는 넘는 행 수로 바꾼다.
- 같은 파일의 보강: 3~6번 검사는 엔진 결함(CBRD-27557, `temp_file_memory_size_in_pages=0` 의 debug assert)으로 서버가 죽은 뒤, cub_master 가 0 설정 그대로 되살린 서버가 스크립트의 `set_membuf 20` 재시작보다 먼저 올라와(`cubrid server start` 는 `Unable to mount disk volume ..._lgat` 로 실패) 5·6번이 연쇄로 실패한다. `set_membuf` 가 재시작 실패를 `abort_test` 로 잡거나 서버가 내려간 것을 확인한 뒤 올리면 연쇄가 끊긴다.

## 2. cbrd_25717_parallel_degree 2번 검사 — 상한 기대식이 엔진 규칙과 다름

### 증상

`PARALLEL(1000)` 의 워커 수를 `pmax = MIN(32, nproc)` 로 기대한다. CI 는 `cores=192 pmax=32` 에 실제 8, develop 빌드 A/B 두 쪽 모두 실제 25.

### 증거

- gha-ci: shell 을 돌린 10-02 이후 run 전부 — 36982998447, 36988875347, 37027696235(develop dispatch, shard 23: `actual='8' expected='32'`), 37034114694, 37083582591, 37104459999, 37123636959, 37123667615, 37160441993, 37167256858, 37168626427(shard 49).
- A/B: `35a7cddb6`, `453da49c8` 모두 `actual='25' expected='32'`. 1·3·4·5번 검사는 통과(`PARALLEL(4)`→4, 0/-1000→직렬, `requested=32 workers=7 partitions=7`). #7866 과 무관하다.

### 원인

엔진의 유효 병렬도는 `MIN(힌트, 코어 수, 입력 페이지 수, 파티션 수, 가용 워커)` 다. 파서가 힌트를 32 로 자르고, 코어 수는 엔진이 sched affinity 와 cgroup CPU 쿼터를 교차해 센다.

- 25: 100000행 입력에 `max_hash_list_scan_size=256k` 면 파티션이 25개라 거기서 잘린다. 파티션 수 공식은 2026-07-22 이후 그대로라 답지를 만든 b319ce1 에서도 25 였다. 5번 검사는 이미 `MIN(요청, 파티션)` 을 쓰면서 2번 검사만 파티션을 빼고 기대했다.
- 8: CI 러너 컨테이너에서 엔진이 보는 CPU 가 8 인 것으로 보인다(`nproc` 은 192). `PARALLEL(4)`→4 와 5번 검사의 7 은 그 안에 있어 통과한다.
- TC PR #4150 에 CI 체크가 없어 CI 환경에서 한 번도 통과한 적이 없다.

### 수정 제안

- 상한 값을 정수로 예측하지 말고, `PARALLEL(1000)` 과 `PARALLEL(32)` 의 워커 수가 같다는 것으로 "상한이 걸린다" 를 검사한다. 코어 수·파티션 수에 영향받지 않는다.
- 32 자체를 보려면 입력을 늘려 SPLIT 의 `partitions` 가 32 를 넘게 하고 기대를 `MIN(32, partitions)` 로 두되, 컨테이너의 CPU 쿼터(엔진의 코어 수)가 32 미만이면 여전히 깨지므로 CI 에서는 앞의 방식이 안전하다.

## 3. _01_no_data_filter.sql — ORDER BY 없는 limit 서브쿼리

### 증상

run 37168626427(sql shard 05) 에서 1회. `select * from (select /*+ recompile */ * from t where ... limit 2,8) t order by i1,i2,i3;` 두 질의의 결과에서 `(2,1,21)` 이 빠지고 `(2,4,24)`, `(4,2,42)` 가 들어왔다. 같은 파일의 iscan 질의들은 모두 답지와 같다.

### 원인

두 서브쿼리는 sscan + inst_num 으로 LIMIT 을 처리해 어떤 8행이 나오는지가 힙 배치 순서를 따른다. 다중 행 INSERT 의 힙 배치가 평소와 달라지면(이 run 에서는 `(2,1,21)` 이 다른 행들 뒤에 놓임) 다른 8행이 나온다. 결과 자체는 LIMIT 의 정의 안에서 맞는 값이다.

### 증거의 한계

120 run 중 이 run 에서만 발생했고 develop 빌드에서 실패한 기록은 없다. 재실행으로 재현되지 않았다. 결함 판단은 플랜(sscan + inst_num)과 diff 의 형태에 근거한다.

### 수정 제안

서브쿼리에 ORDER BY 를 넣어 LIMIT 대상이 정해지게 하거나, 순서가 목적이 아니면 행 집합 대신 개수만 비교한다.

## 4. bug_bts_13242 — 잠금 개수로 덤프 시점을 맞춤

### 증상

`issue_13242.result` 와 답지의 sorted diff 가 어긋난다. run 37168626427(shell shard 16) 에서는 결과에 `LOCK HOLDERS` 블록이 하나 더 있고(`Num holders= 1`, `Object type: Instance of class () = dba.t1.`), 한 클래스의 `Total mode of holders` 가 `SCH_S_LOCK` 대신 `IX_LOCK` + `X_LOCK`, `IS_LOCK` 의 `Count` 가 1 대신 4 다.

### 증거

120 run 중 9 run, 서로 다른 PR 8개 — 36694232105(PR 7901), 36701588264(PR 7957), 36702541200(PR 7977), 36703643879(PR 7993), 36743148780(PR 8001), 36795106556(PR 7969), 36799634228(PR 8059), 36986809351(PR 7943), 37168626427(PR 8022). 머지 베이스는 develop e17fdab25, 2f1a1d5c5, a59140bdd, 30043f492, 15e7dc8b5.

### 원인

`run_test_point` 는 백그라운드 csql 이 SQL 을 실행하는 동안 `export_lockdb` 가 `cubrid lockdb` 를 1초 간격으로 돌려 `Current number of objects which are locked` 가 기대 개수와 같아지는 순간의 덤프를 결과로 쓴다. 개수만 보기 때문에, 잠금을 얻는 도중(또는 앞 포인트의 rollback 이 아직 반영되기 전) 개수가 우연히 기대와 같아지면 그 시점의 잠금 집합이 기록된다. 위 diff 가 그 형태다(인스턴스 X_LOCK 과 클래스 IX_LOCK 이 추가로 잡힌 상태).

### 수정 제안

개수 대신 기대하는 잠금 집합(클래스·모드)이 덤프에 모두 나타날 때까지 기다리거나, 백그라운드 세션이 SQL 을 끝냈다는 표시(예: csql 이 다음 문장을 읽기 전에 남기는 플래그)를 받은 뒤 덤프한다.
