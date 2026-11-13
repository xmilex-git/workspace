# PR-8354 post-ready comments

## CUBRID/cubrid#8354 (engine)

- event: APPROVE
- commit_id: dbbf8abcaccada277202999a76edecc0fab33acd
- inline: 없음

body:

```
develop 309265e6d 와 이 PR(dbbf8abca)의 CI release 빌드로 JIRA 재현 데이터(1M 행, 78그룹, parallelism=4)를 같은 호스트에서 번갈아 7회씩 돌려 봤습니다. ASC 인덱스를 역방향으로 읽는 GROUP BY DESC는 861 ms에서 190 ms로, DESC 인덱스를 정방향으로 읽는 GROUP BY DESC는 594 ms에서 191 ms로 줄었고, 두 질의 모두 trace에 parallel workers: 4 가 붙습니다. 나머지 두 방향 조합과 USING INDEX NONE 해시 플랜은 두 빌드가 같았고, 여덟 질의 모두 결과가 행 순서까지 develop 및 해시 플랜과 같았습니다.
merge-base optdebug 빌드에서는 tc/pr-8354 의 cbrd_27728, cbrd_27664, cbrd_27689 가 parallel workers trace 줄만 빠진 채 NOK 였고 결과 행 차이는 없었습니다.
```

## CUBRID/cubrid-testcases#3970 (TC)

- event: APPROVE
- commit_id: d81914abefb5a625f9cbac132bafe74a1f24a3f7
- inline: 없음
- body: 없음 (빈 본문 Approve)

## CUBRID/cubrid-testcases-private-ex#4680

- 리뷰 없음 (변경 없는 draft)

## Existing threads

- greptile 의 `set trace off` 위치 지적(#3970 cbrd_27728.sql:99)은 새로 달지 않음.
