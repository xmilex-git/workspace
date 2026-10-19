# PR-3708 post-ready comments

## CUBRID/cubrid-testcases#3708

- event: APPROVE
- commit_id: 7d461dc8bd38bec8e3636fe0e29ee3eb2be5aef2
- 기존 Greptile 인라인 (`cbrd_27292.sql:61`, Case 1, 2 직렬 값 검사) 은 다시 달지 않는다. 필요하면 그 스레드에 답글로 동의만 남긴다.

### top-level body

상수 출력 스캔 TC 추가 감사합니다. 최신 develop optdebug(gha-ci 4333ce3a8 빌드)에서 로컬 컨테이너 CTP 로 돌려보니 OK 였고, 결과가 답지와 그대로 같고 코어도 없었습니다. SHOW HEAP CAPACITY 로 봐도 heap 이 145 페이지라 test_mode 임계(32)보다 충분히 큰 것 같습니다. #7767 리뷰 때 말씀드린 WHERE ... HAVING 1=1 경로를 Case 4 로 넣어주셔서 감사합니다.

확인 부탁드립니다
- 본문 검증 표에 수정 전 빌드 결과가 아직 없고 (draft) 로 적혀 있는데, 지금은 리뷰 요청 상태라 수정 전 결과도 채워주시면 좋겠습니다. 코드상으로는 Case 1(row by row), Case 2(temp scan 직렬), Case 4(mergeable list)는 수정 전 빌드에서 trace 가 달라지고, Case 3 은 수정 전에도 빈 pred+rest 강등 때문에 row by row 라 그대로 통과할 것 같습니다. Case 3 은 BUILDVALUE 쪽 변경만 되돌려지는 경우를 지키는 케이스라고 본문에 적어두면 좋을 것 같습니다.

### inline: sql/_36_guava/cbrd_27292/cases/cbrd_27292.sql:26 (RIGHT, Coverage Case 2)

엔진 PR 에서 지운 조건이 TARGET_CLASS 분기 안에 있어서 heap 뿐 아니라 인덱스 스캔에도 걸렸던 것으로 알고 있습니다(PR 본문의 "list/index를 직렬로 강등"). 최신 develop 에서 아래처럼 돌려보니 인덱스 스캔에 parallel workers 와 gather: mergeable list 가 나오고, no_parallel_scan 쪽과 행 수(300000), 값이 같았습니다. heap, list 와 같은 방식으로 Case 5 를 추가해보는 건 어떨까요?
```sql
create table tk (k int);
insert into tk select rownum from db_class a, db_class b, db_class c, db_class d limit 300000;
create index idx_k on tk (k);
insert into rp27292 select /*+ recompile parallel(4) */ 1 from tk force index (idx_k) where k > 0;
```

### inline: sql/_36_guava/cbrd_27292/cases/cbrd_27292.sql:34 (RIGHT, HAVING 1=1 설명)

최신 develop 에서 `select /*+ recompile parallel(4) */ 1 from t27292 having 1=1;` 을 돌려보니 WHERE 없이도 1행이고, rewritten query 에 `having ? <> ?` 가 남고 gather: row by row 였습니다. rewriter 가 지운다기보다는 JIRA 테스트 설명처럼 recompile 없이 `select 1 from t` 의 캐시된 plan 을 같이 쓰는 경우를 말씀하신 것 같은데 맞을까요? 그렇다면 헤더와 본문의 이유를 그쪽으로 고쳐두면 나중에 보는 사람이 덜 헷갈릴 것 같습니다.
