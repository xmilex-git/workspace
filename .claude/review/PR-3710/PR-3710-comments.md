# PR-3710 post-ready comments


## CUBRID/cubrid-testcases#3710

- event: COMMENT
- commit_id: 9c8b6f046541d5b319219799e1686195e3b8bd51

### top-level body

CBRD-26846 에서 추가된 11개 집계를 병렬/직렬 한 문장 비교와 `gather: buildvalue` trace 로 묶어주셔서 감사합니다. 최신 develop optdebug(gha-ci 빌드 4333ce3a8)에서 로컬 컨테이너 CTP 로 `_36_guava/cbrd_26846` 을 돌려봤고, 12개 블록 모두 답지와 같게 OK, 코어는 없었습니다.

확인 부탁드립니다
- 본문에 "수정 전 빌드 검증은 아직 하지 않았습니다(draft)" 로 되어 있는데 PR 은 draft 가 아니라서, 수정 전(d0b290459^) 결과를 채우시거나 문구를 정리해주시면 좋겠습니다. 소스상으로는 수정 전에는 11개 함수가 checker 에서 거절되어 병렬 쪽 trace 가 `gather: row by row` 로 나오니 12개 케이스 모두 trace 블록에서 NOK 가 날 것 같습니다.
- 아래 인라인에 적은 AC 시나리오를 이번에 넣지 않으신다면, 본문에 제외 이유를 남겨주시면 좋겠습니다.

### inline: sql/_36_guava/cbrd_26846/cases/cbrd_26846.sql:82 (RIGHT, Case 2 bit_and(cola) bit_or(cola))

`cola = id % 100` 이면 한 페이지(약 92개 연속 id) 안에 이미 63 과 64 가 들어 있어서, 워커 부분값이 모두 AND = 0, OR = 127 로 같아지는 것 같습니다. 같은 값끼리는 AND 로 합치든 OR 로 합치든 결과가 같으니, BIT_AND/BIT_OR 머지가 잘못되어도 0 / 127 로 PASS 하지 않을까요? 한 행만 다르게 하면 머지가 드러날 것 같은데 어떨까요? 최신 develop 에서 아래 식은 254 / 1 로 병렬/직렬이 같았습니다. Case 1 의 `bit_and(cola)`, `bit_or(cola)` 도 같은 상황입니다.
```sql
bit_and(case when id = 5000 then 254 else 255 end) ba, bit_or(case when id = 5000 then 1 else 0 end) bo
```

### inline: sql/_36_guava/cbrd_26846/cases/cbrd_26846.sql:115 (RIGHT, Case 7 percentile_cont)

JIRA AC 에 "PERCENTILE 범위 오류 케이스 포함" 이 있는데 오류 케이스가 없는 것 같습니다. 엔진 PR 에서 워커가 행 단위 오류를 메인으로 넘기도록 바뀐 부분(`px_scan_task.cpp` 의 `write()` 실패 처리)도 지금은 어느 케이스도 지나가지 않아서, 이 전파가 깨져도 TC 는 통과할 것 같습니다. 최신 develop 에서 `percentile_cont(1.5)` 와 `percentile_disc((select 1.5 from db_root))` 는 병렬(`gather: buildvalue`)/직렬 모두 `Error:-1172`, `json_objectagg(case when id = 5000 then null else to_char(id) end, cola)` 는 양쪽 `Error:-1201` 로 같았습니다. 병렬/직렬 한 쌍씩 추가해보시는 건 어떨까요?

### inline: sql/_36_guava/cbrd_26846/cases/cbrd_26846.sql:125 (RIGHT, Case 8 cume_dist)

AC 의 "다중 정렬키/NULLS FIRST" 는 CUME_DIST/PERCENT_RANK 의 WITHIN GROUP 에 해당하는 것으로 이해하고 있는데, 지금은 단일 키에 NULL 없는 컬럼만 있는 것 같습니다. 일부 행만 NULL 인 컬럼(예: `case when id % 7 = 0 then null else id % 50 end`)을 하나 두고 `cume_dist(50, '0000000005') within group (order by cola, colb desc)`, `percent_rank(20) within group (order by pnull desc nulls first)` 를 병렬/직렬로 비교해보니 최신 develop 에서 PASS 였습니다. 같은 컬럼으로 MEDIAN/PERCENTILE 의 NULL 건너뛰기도 함께 볼 수 있어서, 케이스로 넣어보는 건 어떨까요?
