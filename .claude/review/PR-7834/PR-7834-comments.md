# PR #7834 리뷰 코멘트 (4차, head `b77dfeaa9`, 2026-10-13 게시: 답글 4253983533/4253983675/4253983802/4253983933, 리뷰 5497957135 APPROVE, TC 5497957235/5497957365 APPROVE, 스레드 3개 resolve)

## 엔진 PR CUBRID/cubrid#7834

### 스레드 답글 1 - 루트 순서 (root 4204261299, 작성자 질문 4253615626, `src/optimizer/rewriter/query_rewrite_select.c:4049`) -> 답글만, 열어 둠

선택지 2에 동의합니다. ORDER SIBLINGS BY가 없을 때 루트와 형제 순서는 Oracle, Db2 문서에서도 정해져 있지 않고, 부모 바로 뒤에 자식이 오는 계층 순서는 그대로 유지되는 것 확인했습니다. 다만 사용자가 보는 출력 순서가 바뀌는 것이라, JIRA 사양의 "사용자 가시 결과 불변" 부분에 "ORDER SIBLINGS BY가 없는 질의는 루트/형제 순서가 이전과 다를 수 있음(계층 순서는 유지)"을 사양 변경으로 추가해 주시면 좋겠습니다. `bug_bts_9613` 답안도 TC PR에 같이 부탁드립니다.

### 스레드 답글 2 - 스필 메모리 (root 4204261293, `src/query/query_executor.c:20052`) -> 답글 후 resolve

수정 확인했습니다. 체인 5만(인덱스 없음, release)의 피크 RSS가 상한 128M/8M/64K/0에서 462~466MB로 거의 같아졌고, star 10만도 상한 0에서 487MB였습니다. 결과도 모든 상한에서 같았습니다.

### 스레드 답글 3 - OSB 동순위 (root 4204261307, `src/query/query_executor.c:20523`) -> 답글 후 resolve

네, 동순위 형제 순서는 SQL에서 정해지지 않는 부분이라 말씀하신 대로 두는 것에 동의합니다. 다만 PR 본문과 JIRA의 "128M / 8M / 1M / 0 전 설정 bit-identical" 문구에는 동순위 순서가 제외된다는 점을 같이 적어 주시면 좋겠습니다.

### 스레드 답글 4 - 주석 NIT (root 4216557857, `src/query/query_executor.c:20768`) -> 답글 후 resolve

확인했습니다.

### 새 리뷰

- event: APPROVE (사용자 지시: 세 레포 모두 approve)
- commit_id: b77dfeaa97487d12316927315c559ed6cfb9df06
- 인라인 코멘트 없음

#### 상단 코멘트

10/13 커밋(`b77dfeaa9`) 기준으로 다시 봤습니다. 상한 0 체인의 스필 메모리는 모든 상한에서 같아졌고, 생성기 fast-path도 세션 변수, CASE/IF/DECODE 조건부, IN/BETWEEN, 함수 인자 안에 비결정 항이 있는 11개 형태가 develop과 같은 결과였습니다. `2fed14748`의 COUNT 수정도 PK 테이블에서 START WITH 없는 `COUNT(*)`가 계층 행 수로 나오는 것 확인했습니다. 이 결함은 develop에도 있어서(develop은 테이블 행 수를 돌려줌), PR 본문과 JIRA에 같이 적어 두고 TC도 하나 추가해 주시면 좋겠습니다.

```sql
CREATE TABLE tc_pk (id INT PRIMARY KEY, pid INT);
INSERT INTO tc_pk VALUES (1, NULL), (2, 1), (3, 1), (4, 2);
SELECT COUNT (*) FROM tc_pk CONNECT BY PRIOR id = pid;  -- develop 4, b77dfeaa9 8
```

확인 부탁드립니다
- PR 본문과 JIRA 사양에서 코드와 달라진 부분 갱신 부탁드립니다.
  - 1번 항목 "인덱스가 하나라도 있으면 기존 플랜 유지": `531b2583` 이후 기준(자식 컬럼으로 시작하는 인덱스)으로
  - 5번 항목 "0이면 노드마다 스필": `45abfdbc8` 이후에는 `temp_file_memory_size_in_pages` 기본값에서 256KB 미만 값이 256KB로 동작하는데, 사용자가 바꿀 수 있는 파라미터라 이 하한도 같이 적어 두는 것이 좋겠습니다.
  - 검증 항목 "128M / 8M / 1M / 0 전 설정 bit-identical": 동순위 형제 순서 제외
  - 루트/형제 순서 변경: 루트 순서 스레드에 남긴 대로 사양 변경으로
- gha-ci(run 38329955908)에서 남은 NOK는 답안 갱신 대상으로 보입니다. sql은 CONNECT BY 8건 외에 `_36_guava/cbrd_27510/16_hash_scan_build_keys`(`CONNECTBY` 아래 `ORDERBY` 줄)가 있고, shell은 private-ex `bug_bts_5423`(paramdump에 `max_connect_by_dfs_size` 추가)입니다. shell `cbrd_27121`은 CONNECT BY를 쓰지 않는 케이스라 이 PR과는 무관해 보입니다.
- jihyekim-0님의 JSON 해시 코멘트도 반영 부탁드립니다.

### resolve하지 않는 스레드

- 4204261299 (루트 순서) - 답글만 달고 JIRA/TC 반영까지 열어 둠
- jihyekim-0 스레드 3건(4245033529, 4245045337, 4245870661) - 다른 리뷰어의 스레드라 손대지 않음

---

## TC PR CUBRID/cubrid-testcases#3520

- event: APPROVE
- commit_id: 640156836c22179c671f0bfeac6c78ea60a169e9

#### 본문

답안 변경 확인했습니다. 엔진 PR 코멘트에 남긴 `bug_bts_9613`, `_36_guava/cbrd_27510/16_hash_scan_build_keys` 답안과 COUNT 수정 케이스도 같이 반영 부탁드립니다.

## TC PR CUBRID/cubrid-testcases-private-ex#4178

- event: APPROVE
- commit_id: fb010c31e79c5c015fbaa0747612eadb7b53b05a

#### 본문

shell `bug_bts_5423` 답안에 paramdump의 `max_connect_by_dfs_size` 두 줄 반영 부탁드립니다.
