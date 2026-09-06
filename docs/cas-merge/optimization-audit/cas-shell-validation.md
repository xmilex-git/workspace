# CAS SHM·상태 동기화 보충 검증

대상은 frozen `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`, read-only 코드 감사다.

## 판정

`cas_Shm_stub`은 제거/축소 가치가 큰 process 고정 메모리 후보다. `cas_server_support.cpp:68-69`가 전체 `T_SHM_APPL_SERVER` static 1개와 실제 per-session `thread_local T_APPL_SERVER_INFO cas_As_slot`을 별도로 둔다. boot는 stub 전체를 `memset(sizeof(*shm))`하고 일부 scalar/string config만 채운다(`:109-170`). 구조체 후반에는 ACL 50개, `job_queue[JOB_QUEUE_MAX_SIZE+1]`, shard 256개, `as_info[4096]`, unusable DB 배열이 포함된다(`broker_shm.h:562-668`; limits `:130,137`, `broker_config.h:109`). 실제 bytes는 `sizeof` 측정 없이 만들지 않는다.

그러나 **현재 source를 그대로 둔 채 type만 축소할 수는 없다.** folded source 목록에는 `cas_conn_helpers.c`가 포함되고(`cubrid/CMakeLists.txt:747-776,790-825`), `net_read_int_keep_con_auto` 본문은 `CON_STATUS_LOCK(&(shm_appl->as_info[shm_as_index]),...)`를 참조한다(`cas_conn_helpers.c:236-259`). 다만 folded 정상 경로가 이 본문에 도달한다는 주장은 틀리다. 호출부는 `as_info->cur_keep_con == KEEP_CON_AUTO`일 때만 이를 부른다(`cas_dispatch.c:458-467`). server session begin은 이를 `KEEP_CON_ON`으로 초기화하고(`cas_server_support.cpp:203-215`), folded `CAS_SPEAKER_SOURCES` 검색에서 이후 `cur_keep_con` writer는 찾지 못했다. `cas_common_main.c`의 writer는 별도 legacy CAS main 경로이고, `fn_set_cas_change_mode`는 다른 필드인 `cas_change_mode`를 바꾼다. 그러므로 `as_info[]`는 **컴파일되는 inert legacy AUTO body의 source-level reference**이며, 현재 정상 server runtime 사용의 반례가 아니다. shard credential 배열 접근도 `set_db_connection_info`에 남아 있지만(`cas_dispatch.c:310-320`) boot가 `cas_shard_flag=OFF`로 고정한다(`cas_server_support.cpp:164-169`). job queue/ACL/access_info/unusable DB 배열 역시 folded 정상 경로의 사용을 찾지 못했다. macro/함수 포인터 및 비정상 상태 변조까지 포함한 완전 도달성 증명은 아니다.

`cas_conn_helpers.c:236`은 TLS slot이 아니라 zero-filled static stub array 원소의 semaphore를 가리키지만, 위 KEEP_CON_AUTO gate 때문에 frozen server의 정상 설정에서 실행된다는 근거가 없다. POSIX macro와 wrapper가 실제 `sem_wait/post`인 것은 사실이다(`broker_shm.h:99-110`, `cas_server_support.cpp:534-559`). 이는 런타임 defect 판정이 아니라, 최소 config type을 도입할 때 함께 prune하거나 `#if !SERVER_MODE`/server 전용 AUTO 처리로 제거해야 할 죽은 compatibility body다.

## `CON_STATUS_LOCK` reader/writer 감사

legacy lock을 곧바로 “single owner라 redundant”라고 부를 수 없다. request driver thread가 TLS `as_info`의 `con_status`와 counters를 쓰고(`cas_dispatch.c:273-305,711-778`), `SHOW SESSION STATUS`는 다른 server worker에서 registry를 통해 같은 TLS object 포인터를 읽는다. driver가 pointer를 registry에 publish한다(`driver_session.cpp:621-626`). snapshot은 `registry_mutex`를 잡은 채 `stats_slot->database_user/session_id/counters/log_msg`를 직접 복사한다(`adoption.cpp:281-323`), SHOW scan은 그 snapshot을 호출한다(`server_support.c:284-365`). 코드상 writer는 registry mutex 없이 여러 필드를 갱신하고 reader는 `CON_STATUS_LOCK`을 쓰지 않는다. 따라서 registry mutex가 map 수명 외 pointed fields의 일관성까지 보장하는지는 별도 검증이 필요하고, 기존 CAS semaphore 역시 SHOW reader와 공유되지 않는다. TSAN/실행 검증을 하지 않았으므로 이를 실험으로 확인된 data race라고 단정하지 않는다(COH-10/PAR-02 correctness 우선).

## 안전한 변경 경계

1. 최소 config type으로 컴파일하려면 inert `KEEP_CON_AUTO` body를 server build에서 prune/guard하거나, 그 body가 최소 type을 요구하지 않도록 server 전용 처리를 둔다. 정상 runtime defect 수정의 선결조건으로 표현해서는 안 된다.
2. folded server용 최소 config type을 새로 만들어 실제 scalar/string config만 보유하고 `shm_appl` 직접 접근을 `CAS_SHM_CFG`/명시 accessor로 수렴시키는 것이 구조적 제거 경계다. standalone CAS ABI의 `T_SHM_APPL_SERVER`는 그대로 둔다. `memset` 비용은 boot cold path라 속도 이득을 주장하지 않으며, process RSS/BSS/dirty-page 감소가 목표다(MEM-05, GLOB-03, PHYS-10).
3. SHOW 상태는 TLS object 포인터를 registry에 공개하지 말고, session-owned immutable/atomic stats snapshot을 registry entry에 publish하는 편이 명확하다. 선택지는 (a) driver가 요청 경계마다 registry mutex 아래 plain snapshot copy, (b) counters는 aligned atomics, strings/status는 sequence-lock 또는 mutex 아래 snapshot이다. YCSB hot request마다 전역 registry mutex publish는 병목이 될 수 있으므로 batch/request-end cadence와 SHOW의 허용 신선도를 먼저 정해야 한다(PAR-01/10, COH-01/04). 종료 시 registry erase와 snapshot 수명 순서도 함께 검증해야 한다.

## 미확인

- build/run/sizeof/RSS/TSAN은 수행하지 않았다.
- `JOB_QUEUE_MAX_SIZE`의 최종 매크로 값과 flexible build variants별 구조 크기는 계산하지 않았다.
- shard/access-control/unusable-db 배열의 모든 macro-expanded 또는 간접 call reachability는 완전 증명하지 못했다. `cas_conn_helpers`의 `as_info[]`는 source/type 축소의 반례지만 KEEP_CON_AUTO gate 아래 정상 server runtime에는 inert하다.
- registry erase(`adoption.cpp:365`)와 TLS slot 종료 사이의 전체 호출 순서를 이 보충 감사에서는 끝까지 추적하지 않았다. 현재 map mutex가 pointer lifetime을 충분히 보호하는지도 별도 검증 대상이다.
