# PR #8335 post-ready comments

게시는 사용자 확인 후에만. 게시 직전 세 PR head 재확인 (엔진 e33868668, #3947 389c328ab, #4647 17ac99296).

## CUBRID/cubrid#8335

- event: APPROVE
- commit_id: e33868668a8e5a05e06b6b26dcbd3133aa006508
- inline comments: 없음

### top-level body

정렬 GROUP BY의 ROLLUP 마무리를 `qexec_gby_finalize_group_level` 로 떼어 내서, 직렬 skip은 첫 불일치 키 위치로, 병렬 skip은 리더 병합에서 같은 레벨로 소계를 닫는 흐름으로 읽었습니다. 기존 정렬 경로는 `qexec_gby_put_next` 가 받는 레벨까지 전과 같습니다. debug 빌드(CI tarball)를 SA로 띄워 LIMIT, HAVING, NULL 키, `use_desc_idx` + DESC ROLLUP 등 12개 질의와 티켓 질의(105행)를 develop merge-base 빌드와 대조했고, 결과 행은 모두 같았습니다.

추가로 논의가 필요해 보이는 항목:
- 본문 성능 표의 `ROLLUP + ORDER BY 키 LIMIT 5` 행은 develop과 이 PR이 같은 틀린 답을 내는 질의로 보입니다. 아래 질의에서 LIMIT을 빼면 총계 행 `(NULL, NULL)` 이 첫 행으로 나오는데, LIMIT 3을 붙이면 develop 힙 스캔 경로도 `(0,0) (0,1) (0,2)` 를 돌려줍니다. 이 PR이 만든 동작은 아니지만, 5.5배 수치는 이 표에서 빼거나 주석을 달고 LIMIT이 ROLLUP 소계보다 먼저 걸리는 문제는 별도 이슈로 올리는 것은 어떨까요?

```sql
select g, v, count(*) from t_roll ignore index (i_gv, i_hg) where g >= 0
  group by g, v with rollup order by g, v limit 3;
-- develop, 이 PR: (0,0) (0,1) (0,2)
-- LIMIT 없이 앞 3행: (NULL,NULL) (0,NULL) (0,0)
```

## CUBRID/cubrid-testcases#3947

- event: APPROVE
- commit_id: 389c328abbcfd66cd01bdc451931e2c552774b0b

### top-level body

CI(gha-ci 41016954991, debug/release)에서 `cbrd_27468` 과 재기준한 3건 모두 OK로 확인했습니다.

## CUBRID/cubrid-testcases-private-ex#4647

- event: APPROVE
- commit_id: 17ac99296f48735ba2a0d4d575c0ffa7aa8546a4

### top-level body

CI(gha-ci 41016954991)에서 `_02_having` OK로 확인했습니다.
