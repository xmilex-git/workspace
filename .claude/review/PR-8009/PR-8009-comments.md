# PR #8009 기존 스레드 답글 초안

새 인라인 지적이 아니라 기존 세 스레드에 답할 때 사용할 초안. 게시하지 않음.

## discussion_r4128860310

worker clone의 index scan을 닫는 경로가 없고 다음 open에서 `oid_list`를 덮는 점은 확인했습니다. 기존 코드에도 있어 별도 누수 수정으로 다루는 것이 좋겠습니다. 다만 OID 버퍼는 일반 `malloc`과 공용 풀을 사용하므로 private heap 증가량 대신 할당/풀 반환 횟수나 Valgrind로 확인해야 할 것으로 보입니다. `key_vals`는 빌린 배열이고, 부분 초기화 상태는 `S_CLOSED` 검사만으로 안전성을 보장하기 어려워 open/start 실패 정리도 함께 확인이 필요합니다.

## discussion_r4128860313

플래그가 초기화 성공보다 정리 필요 여부를 뜻한다는 주석에는 동의합니다. 다만 인용하신 MERGEABLE_LIST 실패 경로는 `move_top_error_message_to_this()` 이후 `er_errid()`가 NO_ERROR라서 검사 뒤로 이동해도 플래그가 설정됩니다. 순서를 바꾸면 이 경로에서 누수가 난다는 설명보다는, 부분 초기화도 `write_finalize()` 대상이라는 의미를 남기는 것은 어떨까요?

## discussion_r4128860329

NIT: helper 추출은 괜찮아 보입니다. rewind 지점의 파티션/복수 spec 조건은 유지해야 하고, `new_memoize_storage()`는 메모리 한도 0일 때 기존 storage를 지우기 전에 반환하므로 우선 기존 clear/new 쌍을 그대로 묶는 것은 어떨까요?
