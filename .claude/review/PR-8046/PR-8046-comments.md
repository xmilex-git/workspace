# PR #8046 게시용 리뷰 코멘트

게시 전 사용자 확인 필요. 아래 본문만 GitHub에 올린다.

## CUBRID/cubrid#8046 (엔진 PR)

리뷰 이벤트: APPROVE (메타데이터, 본문에 쓰지 않음)

### 리뷰 본문 (top-level)

MERGE가 만드는 SELECT를 계획 단계에서 직렬로 두고, `compute_parallel_degree()`에서 sysop 안이면 직렬로 돌리는 방향에 동의합니다. CI 빌드(optdebug)로 merge-base(`0d0809963`)와 이 PR head를 각각 새로 띄운 서버에서 돌려 보니, merge-base에서는 `cbrd_27492.sql`과 CBRD-27496 첨부 repro가 모두 첫 MERGE에서 멈췄습니다(리더는 `sort_listfile`, 워커는 `log_sysop_start` -> `rmutex_lock`). head에서는 둘 다 끝났고, `_06_merge_statement` 50건도 모두 통과했습니다.

확인 부탁드립니다
- CBRD-27496도 같은 결함으로 보입니다. 첨부 repro가 merge-base에서 같은 스택으로 멈추고, 이 PR에서는 131072 rows로 끝났습니다. PR 본문과 JIRA에 함께 연결해서 같이 해결 처리하는 것은 어떨까요?
- 회귀 원인은 CBRD-27177에 더해 CBRD-27326(정렬 진입 문턱 2048 -> 256 페이지)도 겹치는 것 같습니다. CBRD-27496 코멘트의 bisect를 보면 기본 conf에서는 CBRD-27326부터 멈추는 것으로 나와서, Remarks에 같이 적어 두면 좋겠습니다.

### 인라인 코멘트

1. `src/query/parallel/px_parallel.cpp:47` (RIGHT)

병렬 index scan(`scan_start_parallel_index_scan`)은 `spec->num_parallel_threads`로 차수를 정하고 바로 `try_reserve_workers()`를 호출해서 이 판정을 거치지 않는 것 같습니다. 이 워커도 결과 list file을 쓰니 같은 temp 파일 경로를 탈 것 같고요. MERGE는 `px_scan_checker`가 하위 spec에 `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN`을 강제해서 이번 범위에는 문제가 없어 보이는데, 주석의 "gates every parallel degree decision"과 PR 본문의 "워커를 띄우는 모든 결정" 범위를 좁히거나, index scan 쪽에도 같은 판정을 넣는 것은 어떨까요?

2. `src/query/parallel/px_parallel.cpp:204` (RIGHT)

NIT: 변경과 관계없는 빈 줄이 추가된 것 같습니다.

```suggestion
```

### 기존 코멘트

- greptile의 "자동 회귀 테스트 부재"(P2) 스레드는 작성자 답변과 greptile 확인으로 정리됐다. 추가로 답할 스레드는 없다.

## CUBRID/cubrid-testcases#3599 (TC PR)

리뷰 이벤트: APPROVE, 코멘트 없음
