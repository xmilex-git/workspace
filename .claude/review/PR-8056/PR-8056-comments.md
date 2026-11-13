# PR #8056 post-ready comments

## CUBRID/cubrid#8056 (engine) — event: APPROVE, commit_id 37cc1a838eaeffdc8a2c6273f19ebb395ace0b35

### top-level

해시 조인이 결과 노드의 출력 목록으로 직접 쓰고 결과 노드는 `list_id` 를 넘겨받는 흐름, 병렬에서 `has_ineligible` 이면 `hjoin_change_to_merge_type_list ()` 로 되돌아가는 경로까지 읽었습니다. CS 모드로 상관 파생 테이블(외부 행마다 재실행), UNION ALL / UNION, CTE 두 번 읽기, 3-way 조인을 develop 과 같이 돌려 보았고, 결과 행은 12문장 모두 같고 head 에서는 그 문장들이 pass through 했습니다.

### inline `src/query/xasl.h:591` (RIGHT)

열려 있는 #8364(CBRD-27870)의 `XASL_OUTPUT_READS_SCAN` 도 `0x1 << 29` 를 씁니다. 뒤에 머지되는 쪽이 `0x1 << 30` 으로 옮겨야 할 것 같은데, 어느 쪽이 옮길지 맞춰 두면 어떨까요?

## CUBRID/cubrid-testcases#3608 — event: APPROVE, commit_id 1849a51a7567047121b7d5aa17b699360c889dc1

### top-level

`temp_scans` / `pass_through` 카운트로 develop 에서는 답이 갈리게 만든 것 확인했습니다. 지금 head(`1849a51a7`)를 #8056 head debug 빌드에서 돌려 12개 case 모두 OK 입니다.

## CUBRID/cubrid-testcases-private-ex#4278 — event: APPROVE, commit_id 08a46bddbfbbcbb23ca0f17a18c53fd4b14eb305

### top-level

병렬·파티션 sub-case 의 행 수·열 합 판정 확인했습니다. 지금 head(`08a46bddb`)를 #8056 head debug 빌드에서 돌려 OK 입니다.
