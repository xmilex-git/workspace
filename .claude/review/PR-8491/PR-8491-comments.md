# PR-8491 post-ready comments

## CUBRID/cubrid#8491 (engine)

- event: APPROVE
- commit_id: a4fec6f8e26a36834c3dde4df0ed0af5ecc6d914
- inline: 없음

body:

```
release, debug 빌드에서 OOS 값을 읽는 trace를 직접 돌려 봤습니다. serial heap, index lookup, partition, parallel heap(buildvalue, mergeable list), parallel partition, parallel UNION 모두 oos 수치가 scan 수치 안에 들어갔고, OOS fetch는 serial과 parallel이 같았습니다(10만 행 중 OOS 값 1000행: release 빌드 4000, debug 빌드 11000).

이 PR 범위는 아니지만 trace를 보다가 궁금한 점이 하나 있습니다. OOS head page는 oos_fix_page_if_oos에서 pgbuf_fix_if_not_deallocated로 fix하고, 이때 disk_is_page_sector_reserved가 page를 2번 더 fix합니다. release 빌드에서 20000바이트 값 200행을 읽으면 oos fetch 800 중 400이 이 할당 확인입니다. 주석에는 해제되었거나 다른 용도로 바뀐 page를 가리키는 참조를 ER_HEAP_OOS_CORRUPTED_RECORD로 끝내려는 것으로 적혀 있는데, scan이 visible로 판정한 heap record의 OOS 참조가 그런 page를 가리키는 경로가 있나요?
```

## CUBRID/cubrid-testcases#4148 (TC)

- event: APPROVE
- commit_id: ca705aa21491bc40502a0fc2d58a190bb4db4818
- inline: 없음 (grill: header `;` NIT 게시 안 함; 아래는 버린 초안)

```
NIT: 주석 안의 ;는 빼는 게 어떨까요? 지금은 줄 중간이라 문장이 나뉘지 않지만, CTP가 ;로 문장을 나눕니다.
```

## cubrid-testcases-private-ex#4850

리뷰 없음 (`tc/pr-8491`에 이 PR의 변경 없음).
