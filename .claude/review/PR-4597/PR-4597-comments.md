# PR #4597 comments

Event: Approve (게시됨, review 5679453202, commit ffbf729f8)

세 케이스 모두 엔진 소스 기준으로 확인했습니다. check_option 은 관리 도구 client 가 일반 슬롯을 먼저 쓰고 예약 슬롯 1개를 더 쓰는 규칙과 unload_lock_timeout 기본값 -1 때문에 11개 중 1개만 실패하는 것이 맞고, oper03 의 lsa1 + 2^48 은 8바이트 정렬된 레코드 시작점과 같을 수 없어 cdc_validate_lsa 에서 매번 오류가 납니다. temp_enc_06 은 file_enc_05/07 과 같은 수정이고, CTP 가 케이스마다 로그를 지우므로 이전 실행 로그가 섞이지 않습니다. cbrd_21506_backupdb 격리도 CBRD-27635 처리 뒤 되돌리는 조건으로 동의합니다.
