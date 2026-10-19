# PR #8176 post-ready comments

## CUBRID/cubrid#8176

- event: APPROVE
- commit_id: d3c1a2245805a22a3929a9e5e38a2b0d4f72370b
- inline: 없음

### top-level body

XASL 생성기 4곳의 재번역만 `set_host_var = 0`으로 돌리는 방향이 깔끔해 보입니다. merge-base(4adcd4090)와 이 PR의 optdebug 빌드로 TC를 돌려 develop FAIL / 수정 PASS도 확인했습니다.

다만 develop에서는 ALTER 없이도 같은 현상이 나는 경로가 하나 더 있는 것 같습니다. 통계가 있는 테이블에 JDBC 바인드로 실행하면, 첫 실행의 bind-peeking(`db_execute_and_keep_statement_local` -> `do_replan_statement_with_bind_peek`)이 `set_host_var = 1`인 채로 `do_prepare_statement`를 다시 부르고, 값이 접힌 XASL이 `?` 텍스트 키로 캐시에 들어갑니다.

```sql
create table rj (id int primary key, n int);
insert into rj select rownum, 0 from db_class a, db_class b limit 300;
update statistics on rj with fullscan;
-- JDBC PreparedStatement로 (n, id) = (1, 1), (7, 2), (5, 3) 순서 실행
update rj set n = 10 + ? where id = ?;
-- develop 4adcd4090: 11, 11, 11 / 이 PR: 11, 17, 15
```

이 경로는 #7476(CBRD-26959)에서 들어온 것으로 보여서, 이 경로만 놓고 보면 회귀인 것 같습니다. 이번 수정으로 함께 고쳐지니 코드는 그대로 두고, PR 본문의 "회귀 아님" / "ALTER 없이는 드러나지 않았습니다" 부분과 JIRA의 영향 범위를 정정하고 CBRD-26959를 링크해 두면 좋겠습니다.

## CUBRID/cubrid-testcases#3771

- event: APPROVE
- commit_id: 09251e10e5937527c40fee1fce76fd8a7f2ac233

### top-level body

develop(4adcd4090) optdebug에서는 7케이스 모두 첫 값으로 고정되어 FAIL, 이 PR 엔진에서는 PASS하는 것을 로컬 CTP로 확인했습니다. 아래 두 가지는 참고로 남깁니다.

### inline 1 — `sql/_36_guava/cbrd_27582/cases/cbrd_27582.sql` line 1 (RIGHT)

참고로 CBRD-27582가 Correct Error라서, QA 규칙(CUBRIDQA-1486)대로라면 `sql/_13_issues/_26_2h/cases/cbrd_27582.sql`과 `answers/cbrd_27582.answer`에 두는 것으로 알고 있습니다.

### inline 2 — `sql/_36_guava/cbrd_27582/cases/cbrd_27582.sql` line 103 (RIGHT)

참고로 통계가 있는 테이블에서는 ALTER 없이 JDBC 바인드만으로도 develop이 첫 값을 계속 씁니다(엔진 PR 코멘트 참고). CTP의 `$int` 바인드로 아래 케이스를 더하면 이 경로도 지킬 수 있을 것 같은데 어떨까요?

```sql
create table t27582_j (id int primary key, n int);
insert into t27582_j select rownum, 0 from db_class a, db_class b limit 300;
update statistics on t27582_j with fullscan;
$int,$1,$int,$1;
update t27582_j set n = 10 + ? where id = ?;
$int,$7,$int,$2;
update t27582_j set n = 10 + ? where id = ?;
select id, n from t27582_j where id <= 2 order by id;
```

develop에서는 11, 11, 이 PR에서는 11, 17이 나옵니다.

## 게시하지 않는 것

- cubrid-testcases-private-ex#4450: 변경 없는 빈 draft. 리뷰도 언급도 하지 않음.
- 기존 코멘트: 사람 리뷰어의 미해결 top-level 코멘트 없음(봇 안내와 `/run` 명령뿐).
