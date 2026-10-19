# PR-3743 post-ready comments

## CUBRID/cubrid-testcases#3743

- event: APPROVE (게시됨: review 5512830472, 2026-10-14)
- commit_id: 2c535bc51a4b1da3ae2a47ee5bdf912406565143

### top-level body

```
tc/pr-8155로 옮겨주셔서 엔진 PR CI(gha-ci 38499031896, optdebug)에서 cbrd_27572가 같이 돌고 답지와 같은 것까지 확인했습니다. 수정 전 develop(bcd6c5936) optdebug에서 케이스를 하나씩 따로 돌려보니 Case 1~4와 Case 6(UNION, qexec_execute_query 끝의 m_qlist_count assert)에서 서버가 종료되고, Case 5, 7, 8, 9는 수정 후와 같은 값이었습니다. 위치만 아래 코멘트처럼 옮겨주시면 될 것 같습니다.
```

### inline: sql/_36_guava/cbrd_27572/cases/cbrd_27572.sql:1 (RIGHT)

```
제가 test.md에 TC 위치를 _36_guava/cbrd_27572로 적어두었는데, 이 이슈가 Correct Error라서 QA 기준으로는 sql/_13_issues/_26_2h/cases/cbrd_27572.sql 과 sql/_13_issues/_26_2h/answers/cbrd_27572.answer 로 가야 하는 것 같습니다. 버그 수정 TC를 _36_guava에 둔 PR 두 건(#3041, #3049)이 같은 이유로 QA에서 돌아온 적이 있어서, 위치만 옮겨주시면 좋겠습니다.
```

## CUBRID/cubrid-testcases-private-ex#4418

- 변경 없음. 리뷰하지 않는다.

## 게시하지 않는 것

- Greptile P2(`cbrd_27572.sql:84`, Case 2-9 계획 확인): grill Q3에서 언급하지 않기로 함. 근거(p1에서 9개 모두 같은 NL inner 계획)는 보고서에만 남긴다.
- 헤더의 debug assert 위치 문구: grill Q2에서 제외.
