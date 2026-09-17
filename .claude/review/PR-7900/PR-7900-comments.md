# PR #7900 게시용 인라인 답글

기존 thread 4002304328, `src/storage/catalog_class.c:4509`에 답글. 옵션 및 DDL 댓글은 중복 게시하지 않음.

코드를 더 따라가 보니 `_db_class`는 `mvcc_is_mvcc_disabled_class()`의 제외 대상이 아니고, `catcls_update_class_stats()`도 `UPDATE_INPLACE_NONE`으로 새 버전을 기록합니다. 반면 `heap_scancache_start_internal()`은 전달된 NULL snapshot을 그대로 보관하고, `heap_get_visible_version_internal()`은 snapshot이 없으면 가시성 검사와 이전 버전 탐색을 건너뜁니다.
따라서 이 probe를 최신 커밋 버전 조회로 보기는 어려운 것 같습니다. 두 probe에 `mvcc_satisfies_committed`를 적용한 별도 snapshot을 전달하는 방향으로 수정하고, 선행 통계 기록 후 후행을 진입시켜 COMMIT/ROLLBACK 양쪽을 확인하는 것이 좋겠습니다. 여기까지는 실행 재현이 아닌 코드 확인 결과입니다.
