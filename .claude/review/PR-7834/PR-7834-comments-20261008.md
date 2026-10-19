# PR #7834 리뷰 코멘트 (3차, head `31f218513`, 2026-10-08 게시: 답글 4216556826, 4216557173 / 리뷰 5453652050 REQUEST_CHANGES, NIT 4216557857 / 스레드 3개 resolve)

## 엔진 PR CUBRID/cubrid#7834

### 스레드 답글 1 - 스필 메모리 (root 4204261293, `src/query/query_executor.c:20052`)

수정 확인했습니다. star 10만은 상한 0에서도 피크 RSS가 6843MB에서 487MB로 줄었습니다. 그런데 깊은 체인은 아직 그대로인 것 같습니다. `id = pid + 1` 인 체인 5만(인덱스 없음, release)의 피크 RSS가 128M/8M/64K에서는 790~806MB인데, 0에서는 3787MB였습니다.

```sql
SET SYSTEM PARAMETERS 'max_connect_by_dfs_size=0';
SELECT COUNT (*), MAX (LEVEL) FROM chain START WITH id = 150001 CONNECT BY PRIOR id = pid;
```

`qexec_connect_by_spill_if_needed` 는 호출마다 상주 구간 `[path_scan_from, path_top)` 만 청크로 쓰는데, 상한 0에서는 그 구간이 직전 노드 하나라서 청크 크기 하한과 관계없이 레벨마다 temp 파일과 membuf가 하나씩 생기는 것으로 보입니다. `max_connect_by_dfs_size` 의 하한을 membuf x `CONNECT_BY_SPILL_CHUNKS_PER_LIMIT`(256KB)로 올리거나, 내부 유효 상한을 그 값으로 잡는 것은 어떨까요?

### 스레드 답글 2 - OSB 동순위 (root 4204261307, `src/query/query_executor.c:20523`)

2000건, 8000건에서 맞는 것 확인했습니다. 다만 형제가 10만 건 정도로 많으면 상한에 따라 동순위 순서가 다시 갈리는 것 같습니다. pid 인덱스 star 10만(`k = MOD (x, 7)`)에서 아래 결과가 develop, 상한 65536, 0은 같았고(k=1 그룹이 id 86488부터), 상한 128M과 기본값은 입력 순서(id 3부터)로 나왔습니다. 인덱스 없는 같은 테이블(해시 경로)도 기본값과 0의 순서가 달랐습니다.

```sql
SELECT id FROM star_i START WITH id = 1 CONNECT BY PRIOR id = pid USING INDEX i_star_i_pid ORDER SIBLINGS BY k;
```

`qexec_connect_by_sort_siblings` 는 안정 merge sort인데, 스필 경로의 `qfile_sort_list_with_func` 은 입력이 크면 동순위의 입력 순서를 지키지 않아서 생기는 것으로 보입니다. develop 순서도 외부 정렬이 만든 것이라 그대로 맞추기는 어려울 것 같고, 스필 정렬에 입력 순번을 마지막 키로 더해 모든 설정에서 입력 순서로 맞추는 것은 어떨까요?

### 새 리뷰

- event: REQUEST_CHANGES
- commit_id: 31f2185135a1d799f5526ead2d0d565ad780d50f

#### 상단 코멘트

10/08 커밋(`31f218513`) 기준으로 다시 돌려 봤습니다. 세션 변수와 저장 함수 생성기는 develop과 같이 4행이 나오고, 사이클 배터리와 형제 2000건 OSB 동순위도 모든 상한에서 develop과 같았습니다. 체인 25k/50k/100k/200k도 0.32/0.39/0.53/0.80초로 선형이 됐고, optdebug CTP sql/medium은 이전 head와 실패 목록이 같고 core는 없었습니다. 스필 메모리와 OSB 순서는 기존 스레드에 답글로 남겼습니다.

확인 부탁드립니다
- PK만 있는 테이블의 루트 순서(`bug_bts_9613`)는 말씀하신 수정이 올라오면 다시 보겠습니다.
- PR 본문 1번 항목이 아직 "인덱스가 하나라도 있으면 기존 플랜 유지"로 되어 있어서, `531b2583` 이후 기준(자식 컬럼으로 시작하는 인덱스)으로 갱신이 필요해 보입니다. 테스트 항목의 "128M / 8M / 1M / 0 전 설정 bit-identical" 문구도 OSB 스레드 내용과 같이 봐 주시면 좋겠습니다.
- head에서는 아직 gha-ci가 돌지 않았습니다. 루트 순서 수정 후 `/run all` 한 번 부탁드립니다.
- TC PR #3520은 10/07 코멘트(답안 7개 갱신, `sql/_36_guava/cbrd_27329/` 신규 케이스)가 아직 반영되지 않았습니다.

#### 인라인 1 - src/query/query_executor.c:20768

NIT: `4ec087b4a` 로 청크가 최소 membuf 크기가 되면서, 이 주석의 "a tiny limit keeps chunks tiny" 와 `CONNECT_BY_SPILL_CHUNKS_PER_LIMIT` 주석의 "one reload re-admits at most a quarter" 는 상한이 256KB보다 작을 때 맞지 않게 된 것 같습니다. 같이 고쳐 주시면 좋겠습니다.

### resolve할 스레드 (고쳐짐)

- 4204261282 (`:18713` 생성기 fast-path) - `b9355ba3a`, `31f218513`, 세션 변수/저장 함수 4행 확인
- 4204261315 (`:18326` 사이클 필터) - `fe7a96600`, 체인 선형 확인
- 4204261319 (`:20541` 정렬 실패 NIT) - `6a126824e`

열어 두는 스레드: 4204261299 (루트 순서), 4204261293 (스필 메모리), 4204261307 (OSB)

---

## TC PR CUBRID/cubrid-testcases#3520

새 리뷰 없음. 10/07 Request changes(review 5439064426) 뒤로 변경이 없어 그대로 유지하고, 엔진 PR 상단 코멘트에서 다시 알립니다.

## TC PR CUBRID/cubrid-testcases-private-ex#4178

빈 draft라 리뷰하지 않습니다.
