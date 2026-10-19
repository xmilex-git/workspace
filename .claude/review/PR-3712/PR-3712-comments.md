# PR-3712 post-ready comments


## CUBRID/cubrid-testcases#3712

- event: COMMENT
- commit_id: bb3ada0182ea2477a7b22ee4f4a2e4bbc76e46d2

### top-level body

filtered index 병렬 인덱스 스캔 케이스 추가 감사합니다. 로컬 컨테이너 CTP(optdebug, gha-ci develop 아카이브 빌드)로 돌려봤습니다.

| 빌드 | 결과 |
|---|---|
| 최신 develop 4333ce3a8 (optdebug) | OK, 코어 0 |

비교 쿼리 14개에 recompile 과 show trace 를 붙여 따로 돌려보니 PARALLEL(8) 쪽은 모두 parallel workers ... gather: buildvalue, NO_PARALLEL_SCAN 쪽은 직렬이었고, 필터 이탈 UPDATE 뒤에도 같았습니다.

확인 부탁드립니다
- 본문에 수정 전 빌드 검증은 아직이라고 되어 있는데 PR 이 ready 상태라, 결과를 채워주시면 좋겠습니다. 코드상으로는 수정 전 엔진이 filtered index 를 XASL 생성 단계에서 직렬로 돌리니, PASS 14줄은 그대로이고 trace 5블록의 parallel workers 줄만 빠져서 NOK 가 날 것으로 보입니다.

### inline: sql/_36_guava/cbrd_27060/cases/cbrd_27060.sql:27 (RIGHT, 헤더 autocommit 문구)

헤더의 "(autocommit off)" 때문에 CTP 가 첫 문장을 autocommit 제어 명령으로 처리하는 것 같습니다. CQT 의 `ConsoleBO.isPropOff` 가 문장 전체에서 `autocommit\s+off` 를 찾는데 `/* */` 헤더가 첫 문장에 붙어 가서, `drop table if exists ft;` 대신 `setAutoCommit(false)` 만 실행됩니다. 답지도 문장 59개(단독 autocommit 2줄 제외 57)에 블록 56개로 drop 블록이 빠져 있고, 같은 setup 을 헤더 없이 돌리면 `0, 0, 40000` 으로 시작했습니다. 문구를 바꾸고 답지 맨 앞에 `0` 블록 하나를 추가하는 건 어떨까요?
```suggestion
 * open transaction with auto-commit disabled, so the old entries can never be
```

### inline: sql/_36_guava/cbrd_27060/cases/cbrd_27060.sql:146 (RIGHT, Plan after the UPDATE 의 show trace)

JIRA AC 에 행 반환(list-scan) 경로도 있는데, 지금 케이스는 모두 집계라 buildvalue gather 만 지나는 것 같습니다. develop 4333ce3a8 에서 아래처럼 derived table 로 행을 받으면 gather: mergeable list 로 병렬이 걸리고, UPDATE 전 30000 / 450015000, 후 27000 / 405021000 으로 NO_PARALLEL_SCAN 쪽과 같았습니다. UPDATE 전후로 한 쌍씩 추가해보는 건 어떨까요?
```sql
select /*+ recompile */ count(*), sum(cast(x as bigint)) from (select /*+ no_merge PARALLEL(8) */ id x from ft where del = 0 and grp between 0 and 30000 using index idx_flt(+)) t;
```

### reply to 4254096708 (cbrd_27060.sql:183)


develop 4333ce3a8 에서 비교 쿼리 14개에 trace 를 붙여 돌려보니 Case 9/12/13 을 포함해 PARALLEL(8) 쪽은 모두 parallel workers ... gather: buildvalue 였습니다. 지금은 PARALLEL(8) 쪽이 실제로 병렬로 돌고 있어서, 회귀 감지용으로 trace 를 더 남길지는 작성자분 판단에 맡기면 될 것 같습니다.
