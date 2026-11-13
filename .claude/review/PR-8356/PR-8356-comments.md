# PR #8356 post-ready review comments (2차)

1차 게시분(2026-11-06, 엔진 COMMENT 5794418992, TC #3975 APPROVE 5794419397)은 `.git_ignored_dir/scratch/pr8356/r2/PR-8356-comments.r1.md` 에 있다.

## CUBRID/cubrid#8356 (engine)

- event: APPROVE
- commit_id: `14e1aea9c9196414ae100bfa24b89946e02caf30`
- inline: 없음

top-level:

```
답변과 14e1aea9c 반영 모두 확인했습니다. issue_9495_synctool 은 merge-base(e98bdd885) optdebug 빌드에서 같은 DB 상태로 `prepare ... where s1 = ?` 를 돌려 봤는데, '@' 는 `ri` 인덱스 스캔으로 0행, 'AE' 는 64행이 나와 develop 도 인덱스로는 그 행을 찾지 못하는 것을 확인했습니다. 이 PR 빌드에서는 외부 조인이 `ri` idx-join 으로 646행, `using index none` 이면 1088행입니다. XASL_NL_PER_ROW_PARTITIONS 는 gen_outer 에서만 붙고 그때 XASL_IS_PER_OUTER_ROW 도 늘 참이라, trace 병합 조건 단순화도 판정이 같습니다.

shell 의 `issue_21654_server_side_loaddb/tran_info` NOK 는 loaddb 실행 중 tranlist 를 폴링하는 타이밍 TC 이고 60058202c 에서는 통과했으니, `/run rerun 42178733654` 로 보시면 될 것 같습니다.
```

## CUBRID/cubrid-testcases#3975 (TC, public)

- 새 리뷰 없음. 1차 APPROVE(5794419397, `d362cdc2`) 이후 head 변경 없음.

## CUBRID/cubrid-testcases-private-ex#4684 (TC, shell)

- event: APPROVE
- commit_id: `10d781549e72e62c4014dd38ab3cd8072834ed2b`
- body: 없음
- inline: 없음

## Existing threads

- 1차 inline 4건과 greptile 스레드는 작성자 답글로 닫혀 있어 추가 답글 없음.
