# PR #8009 최근 리뷰 3건 검토

**PR:** https://github.com/CUBRID/cubrid/pull/8009
**HEAD SHA:** `616c704bdd793191efef38e65b616971c909ab05`
**검토일:** 2026-09-29
**범위:** soheejung-cs가 2026-09-29 작성한 최근 인라인 코멘트 3건의 타당성. PR 전체 승인 판정은 아님.

> **TL;DR** (작성자 확인 필요): 스캔 close 누락은 정적 근거가 있는 기존 문제다. 초기화 플래그 주석과 memoize 함수 추출은 선택적 개선이며, 각 코멘트의 설명 또는 제안에 보완이 필요하다.

## Summary

- **변경 요약**: 스캔 자원 해제, 초기화 플래그 의미, memoize reset 제안을 현재 HEAD와 대조했다.
- **주요 이슈**: OID 버퍼 누수 근거는 타당하지만 private heap 측정 제안은 대상 할당 방식과 맞지 않는다.
- **확인 필요 사항**: 스캔 close 수정은 정상 종료와 부분 초기화 실패를 각각 검증해야 한다.

## Findings

### Scan cleanup

[원 코멘트](https://github.com/CUBRID/cubrid/pull/8009#discussion_r4128860310): 핵심 지적 타당. 이 PR 이전부터 존재하므로 신규 회귀로 분류하지 않는다.

- `px_scan_task.cpp:203,348`에서 index scan을 열고, `:532-558`의 MERGEABLE_LIST/BUILDVALUE_OPT 종료에서는 닫지 않는다. `scan_close_scan()`은 XASL_SNAPSHOT 분기에만 있다(`:564`).
- `query_executor.c:2018-2077`의 `qexec_clear_access_spec_list()`는 index scan의 `oid_list`, `bt_attr_ids`, `copy_buf` 반환을 대신하지 않는다. `xasl_cache.c:2337`의 `xcache_retire_clone()`도 스캔을 닫지 않는다.
- `scan_manager.c:3604`에서 OID 버퍼를 얻고, 다음 open의 `:3525`에서 포인터를 NULL로 덮는다. 반환은 `scan_close_scan()`의 `:5451`에 있다. 캐시된 실행 계획 사본인 XASL clone의 재사용 시 버퍼를 잃는 경로가 성립한다.
- 단, `key_vals` 배열은 `indx_info->key_info.key_vals`를 빌린 포인터(`:3668`)이며 close는 NULL로만 바꾼다(`:5433`). 독립 할당 버퍼 누수와 동일하게 묶으면 부정확하다.
- OID 버퍼는 `scan_alloc_oid_list()`의 일반 `malloc`(`:1327,1336`)과 공용 재사용 풀을 쓴다. private heap 증가량만으로 검증하지 말고, 풀 반환/새 할당 횟수 또는 Valgrind 누수 근거를 확인해야 한다.
- 수정 방향은 worker가 연 scan을 값/계획 정리 전에 end/close하는 것이다. 그러나 `status != S_CLOSED`만으로 모든 부분 초기화가 안전하다고 단정하면 안 된다. `scan_init_scan_id()`는 세부 필드 초기화 전에 S_OPENED를 설정하며(`:3189`), index open은 root fix 단계에서도 반환한다(`:3500`). open/start 단계별 획득 상태와 실패 정리를 함께 검토해야 한다.

### Handler flag comment

[원 코멘트](https://github.com/CUBRID/cubrid/pull/8009#discussion_r4128860313): 주석 추가 취지는 타당하지만, 인용한 실패 사례로 순서 이동의 결함을 입증하지 못한다.

- `px_interrupt.hpp:79-87`의 `move_top_error_message_to_this()`는 현재 오류를 빈 오류 객체와 swap한다. MERGEABLE_LIST의 인용된 조기 반환은 이를 호출하고 interrupt를 설정한다(`px_scan_result_handler.cpp:277-279,285-287`).
- 이 경로에서는 `er_errid() == NO_ERROR`이므로 플래그 설정을 검사 직후로 옮겨도 실행된다. “Greptile 경로에서 순서만 바꾸면 정리가 누락된다”는 설명은 정정해야 한다.
- 현재 플래그 위치는 유지하고, 의미를 “모든 초기화 성공”이 아니라 “handler 초기화를 시도하여 finalize가 필요함”으로 설명하는 주석을 권한다. 개별 writer 초기화 완료 여부는 별도의 `tl.write_initialized`가 나타낸다.

### Memoize helper

[원 코멘트](https://github.com/CUBRID/cubrid/pull/8009#discussion_r4128860329): 중복 제거 제안으로 타당하며 필수 결함 수정은 아니다.

- `query_executor.c:8213,8271,8302`의 clear/new 쌍은 실제로 동일하다. helper를 추출하더라도 rewind 지점의 `parts != NULL || spec_list->next != NULL` 조건은 보존해야 한다.
- `memoize.cpp:1053-1056`에서 new가 기존 storage를 clear하는 것은 맞다. 다만 그보다 앞선 `:1048-1051`에서 메모리 한도 0이면 clear 없이 반환한다. 따라서 두 호출이 모든 입력 상태에서 동일하다는 설명은 성립하지 않는다.
- 실행 중 한도가 0으로 바뀌면서 기존 storage가 남는 실제 경로는 이번 검토에서 확정하지 않았다. 이는 현재 PR 결함 판정이 아니라 제안된 대체의 전제 조건이다.
- 보수적인 함수 추출은 기존 clear/new 쌍을 그대로 감싸고 세 호출 지점의 조건을 유지한다. new 단독으로 단순화하려면 한도 불변 조건을 먼저 확인한다.

## Validation

- 현재 PR HEAD와 로컬 CBRD-27484 HEAD 일치 확인. base `fa6664e1`과 비교하여 close 누락이 기존 코드에도 있음을 확인했다.
- 반증 재검토: handler/iterator 종료, XASL clear와 clone 반환, OID 할당/풀 반환, 오류 이동 후 errid, memoize 한도 0 조기 반환을 대조했다.
- 정적 검토만 수행. 빌드, CTP, 런타임 누수 측정은 실행하지 않았다. 엔진 코드와 GitHub는 변경하지 않았다.
