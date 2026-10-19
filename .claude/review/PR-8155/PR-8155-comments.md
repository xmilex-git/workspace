# PR #8155 post-ready review comments

## CUBRID/cubrid#8155 (engine)

- event: APPROVE
- commit_id: 386488ab605f5c1001a30bb09bb50a2cbc61cf1c
- inline comments: 없음

body:

```
TC가 봇이 만든 `tc/pr-8155`(cubrid-testcases#3743)가 아니라 별도 브랜치 `CBRD-27572`(cubrid-testcases#3742)에 올라가 있는 것 같습니다. 그래서 `/run all`의 sql 테스트는 `tc/pr-8155`의 초기 커밋(4f8f6ee1b)으로 돌았고, `cbrd_27572`는 CI에서 실행되지 않은 것으로 보입니다. #3742의 커밋을 `tc/pr-8155`로 옮겨서 CI에서 같이 확인하는 것은 어떨까요?
```

## TC PRs

- cubrid-testcases#3742 / #3743, cubrid-testcases-private-ex#4418: 별도 리뷰 없음 (엔진 PR 본문에서 언급).
- Greptile의 #3742 인라인 코멘트(`memoize_memory_limit=2M` -> `default`)는 이미 달려 있으므로 다시 올리지 않는다.
