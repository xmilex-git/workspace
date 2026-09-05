# XASL stream 직렬화/역직렬화 제거 가능성 — 사실 조사 (#214)

- 대상 코드: cas-merge tip `~/dev/worktrees/wf143-gate` (detached @7117c8a66 == xmilex/cas-merge). 비교: upstream develop `~/dev/cubrid`.
- 인용 표기: `path:line` 은 wf143-gate 트리 기준. develop 과 차이가 있는 파일만 별도 표기.
- 선행 결정: #124 D3 "stream 직렬화 유지가 기본 노선, in-memory 는 실측 후 성능 트랙", D4 "native 진입점은 MOP 없는 서버 의미론 값". 본 문서는 그 '실측 전 사실 인벤토리'다.

## 0. 요약표

| 질문 | 답 | 근거 |
|---|---|---|
| 캐시 히트 시에도 unpack 하나 | **아니다(대개)**. xcache 엔트리는 stream 과 **unpack 완료된 XASL 클론 풀**을 둘 다 보관. 실행은 클론 풀에서 하나를 꺼내 쓰고 반납한다. unpack 은 클론 풀이 비었을 때만 일어난다. | `xasl_cache.h` `xasl_cache_ent.stream`/`cache_clones`; `xasl_cache.c:1095-1133`, `:2324-2386` |
| pack 은 언제 | **컴파일 시 1회**. prepare 히트(sha1 조회)는 stream 없이 XASL_ID 만 받으므로 pack 자체가 없다. 비-prepared 문장(`prepare_and_execute`)은 매번 pack+unpack, 캐시 미투입. | `execute_statement.c:15307-15408`, `query_manager.c:1788`, `:1224` |
| 스레드 | 컴파일·pack·prepare·execute·unpack 전부 **요청을 받은 그 워커 스레드**에서 in-process. 병렬 스캔 워커만 별도 스레드에서 자기 몫을 클론/재-unpack. | `network_interface_cl.c:7489-7536`, `:7745-7835`; `px_scan_task.cpp:570-611` |
| 폴드가 stream 경로에 바꾼 것 | 거의 없음. `xasl_to_stream.c` 의 정적 버퍼를 `thread_local` 로(49줄), debug 왕복검증의 thread 슬롯 save/restore(결함 5). `stream_to_xasl.c`·`xasl_cache.c`·`xasl_stream.cpp` **diff 0줄**. `query_manager.c` 는 packed→native DB_VALUE 진입점(#124 D4)만. | `diff` 결과 §1.6 |
| 폴드 seam 의 불필요 복사 | prepare 시 stream 을 **malloc+memcpy 1회 더** 복제한다(SA 분기 축자 승계). 양쪽 모두 plain malloc 이라 소유권 이전으로 대체 가능. | `network_interface_cl.c:7495-7512`, `xasl_to_stream.c:7938-7942`, `xasl_cache.c:1590,1784` |
| stream 을 유지해야 할 이유 | ① CS 빌드(libcubridcs: csql -C, cub_admin 유틸, 브로커군)와 서버 핸들러 `sqmgr_*` 가 와이어 포맷 그대로 살아 있음 ② 필터/함수 인덱스 술어가 **디스크 카탈로그에 stream 으로 영속** ③ 클론 = stream 에서 unpack 하는 것이 유일한 "깊은 복사" 기계(병렬 워커 포함) ④ MOP→OID 정규화가 pack/unpack 경계에서 공짜로 일어남 ⑤ 컴파일 산출 XASL 의 메모리는 parser arena, 실행 XASL 은 private heap unpack arena — 소유·수명 모델이 다름 | §2 |
| 비용 측정 | pack/unpack **직접 측정 없음**. #177 YCSB 프로파일 상위 25 에 `xts_*`/`stx_*` 부재, memmove 3.7-4.1% 는 cursor 결과 디스크립터 복사로 귀속. 존재 카운터는 개수(hit/miss/add)뿐, 시간·크기 분포 없음. | §3 |
| 후보 판정(사전) | (a) 공유 unpacked + copy-on-execute: 가변 필드가 plan 과 같은 구조체에 산재 → 구조 분리 대공사, 현행 클론이 이미 '깊은 복사 캐시'. (b) 컴파일=실행 세션 직결: `prepare_and_execute` 경로(비-prepared)에만 의미, MOP 정규화·arena 수명·병렬 워커 packed_xasl 의존이 선결. (c) debug 왕복검증 생략: NDEBUG 전용·json_table 한정 → release 비용 0, 성능 후보 아님. (d) 값싼 것: seam memcpy 제거, 클론 풀 크기/미스 카운터. | §4 |

## 1. 폴드 후 경로 추적

### 1.1 컴파일 → pack (클라이언트 절반, 요청 워커 스레드)

- `do_prepare_select` (`src/query/execute_statement.c:15240`): sha1 계산 `:15292-15293` → `prepare_query(contextp, &stream)` 를 **stream.buffer == NULL 로 먼저 호출**(캐시 조회) `:15310-15312`. 히트면 `stream.xasl_id` 가 채워지고 헤더 플래그로 LIKE/LIMIT 재컴파일 판정 `:15327-15345`. 미스(`stream.xasl_id == NULL`, `:15356`)일 때만 `parser_generate_xasl` `:15365` → `xts_map_xasl_to_stream` `:15380` → `prepare_query` 재호출(stream 포함) `:15406-15408`.
- `xts_map_xasl_to_stream` (`src/query/xasl_to_stream.c:287-378`): 직렬화 상태가 파일 정적 변수 — 폴드에서 `CSQL_PARSER_TLS`(SERVER_MODE 에서 `thread_local`, `src/parser/csql_parser_tls.h:38-46`)로 스레드화 `:72-84`. 버퍼는 `malloc`/`realloc` 성장 `:7912-7949`(단위 `STREAM_EXPANSION_UNIT`, `src/xasl/xasl_stream.hpp:52`). 결과 소유권은 호출자(`free_and_init`).
- pack 은 **클라이언트 모자**에서 돈다: `mr_data_writeval_object` (`src/object/object_primitive.c:5202-5260`) 는 `db_on_server && !csc_bracket_is_active()` 가 아니면 클라이언트 본체로 들어가 MOP → `WS_OID` 로 OID 를 기록한다. 즉 컴파일러가 XASL 상수에 넣은 `DB_TYPE_OBJECT`(MOP) 값은 stream 에 OID 로 떨어진다.
- 비-prepared 경로: `execute_statement.c:15116-15125`(및 동형 10018/11392/12038/15380/18402 등 `grep xts_map_xasl_to_stream` 15곳) → `prepare_and_execute_query` (`src/query/query_cl.c:158`) — 캐시 미투입.

### 1.2 prepare seam (`network_interface_cl.c`, SERVER_MODE 분기)

- `qmgr_prepare_query` `:7383`; `#else /* CS_MODE */` 분기 `:7489-7536` 가 SA·SERVER_MODE 공용. `enter_server()` `:164`(db_on_server 증가·er stack) → **stream 을 `malloc`+`memcpy` 로 복제** `:7503-7512` (주석: "XASL cache will save the stream ... suppose the stream buffer was allocated using malloc") → `xqmgr_prepare_query(thread_p, context, &server_stream)` `:7522` → `free_and_init(server_stream.buffer)` `:7525` → `exit_server`.
- develop 의 SA 분기와 문자 동일(develop `network_interface_cl.c` 동일 오프셋 `+107..+144`). 복제가 필요했던 근거는 SA 시절 가정이며, `xts` 버퍼도 plain `malloc` (`xasl_to_stream.c:7938`) 이므로 소유권 이전으로 대체 가능(§4 d).

### 1.3 서버 절반: `xqmgr_prepare_query` → xcache

- `src/query/query_manager.c:1013`: `xcache_find_sha1(..., XASL_CACHE_SEARCH_FOR_PREPARE)` — 히트면 `XASL_ID_COPY` 후 반환; 헤더 요청 시 `qfile_load_xasl_node_header(cache_entry_p->stream.buffer)` (`src/query/list_file.c:1128` → `stx_map_stream_to_xasl_node_header`, `src/query/stream_to_xasl.c:176`) — **캐시 히트 경로에서 stream 을 읽는 유일한 지점**(헤더 int 몇 개). 미스면 stream 헤더에서 `dbval_cnt/creator_oid/class_oid_list/locks/tcard` 를 `or_unpack` 하고 `xcache_insert`.
- `xcache_insert` (`src/query/xasl_cache.c:1465`): 삽입 성공 시 `(*xcache_entry)->stream = *stream` `:1590` 로 **버퍼 소유권을 엔트리가 가져가고** 호출자 포인터를 NULL `:1784`; 이미 있으면 `free_and_init(stream->buffer)` `:1773`. 엔트리 해제 시 stream·클론 전부 free `:557-615`.
- 엔트리 구조 (`src/query/xasl_cache.h`): `XASL_STREAM stream`(packed bytes) + `XASL_CLONE *cache_clones / one_clone / n_cache_clones / cache_clones_capacity / cache_clones_mutex`. `XASL_CLONE = { xasl_unpack_info *xasl_buf; XASL_NODE *xasl; }`. 키 `XASL_ID = { sha1, cache_flag, time_stored }` (`src/storage/storage_common.h:915-922`).

### 1.4 execute seam → 클론 획득 → 실행 → 반납

- 클라이언트 절반: `do_execute_select` `:15900`; `statement->xasl_id` 없으면 no-op `:15913-15917`; `execute_query(statement->xasl_id, ..., parser->host_variables, ...)` `:16026-16027` (`query_cl.c:106`) → `qmgr_execute_query` (`network_interface_cl.c:7565`).
- seam `:7745-7835`: host 변수 배열을 `db_private_alloc` 으로 재할당하며 **OBJECT → OID 정규화**(`ws_identifier`) `:7772-7790`(#124 D4 규약, `qmgr_prepare_and_execute_query` `:7920-7960` 동형) → `xqmgr_execute_query(thread_p, xasl_id, ..., server_db_values, ...)` `:7806-7808` → `qmgr_attach_first_page_copy` `:7811`(결과 첫 페이지 `malloc(DB_PAGESIZE)`+`memcpy`, `:200-240` — XASL 무관하나 같은 seam 의 per-execute 복사).
- 서버 절반 `xqmgr_execute_query` (`query_manager.c:1309`): `xcache_find_xasl_id_for_execute` `:1374` → 결과 캐시 조회 → `qmgr_process_query(thread_p, xclone.xasl, NULL, 0, ...)` `:1548` → `xcache_retire_clone` `:1641`.
- `xcache_find_xasl_id_for_execute` (`xasl_cache.c:969`): sha1 조회(RT 임계 → `ER_QPROC_XASLNODE_RECOMPILE_REQUESTED` `:994-998`) → `time_stored` 일치 검사 `:1002-1003` → 관련 클래스 전부 `lock_object` `:1053-1075`(#177 프로파일의 "주황" 4.2%) → 삭제 마크 재확인 `:1079` → **클론 풀에서 pop** `:1095-1125`(뮤텍스 `cache_clones_mutex`) → 풀이 비면 **전역 heap 으로 전환**(`db_change_private_heap(thread_p, 0)` `:1128`) 후 `stx_map_stream_to_xasl(..., use_xasl_clone=true, stream.buffer, ...)` `:1133`.
- `xcache_retire_clone` `:2324-2386`: `n_cache_clones < max_plan_cache_clones && entry_size < xcache_Max_plan_size` 면 풀에 push(`assert(IS_XASL_INITIAL_STATUS(xclone->xasl->status))` `:2327` — 실행이 `qexec_clear_xasl` 로 초기 상태로 되돌려 놓았다는 계약), 아니면 `xcache_clone_decache` `:2302`(`free_xasl_unpack_info`).
- 파라미터: `max_plan_cache_entries` 기본 1000, `max_plan_cache_clones` 기본 1000(0 이면 클론 비활성 → 매 실행 unpack) (`src/base/system_parameter.c:2260-2281`). 메모리 상한 `Hard = entries×128KB`, `Soft = 0.8×Hard`, `Max_plan_size = (Hard−Soft)/UNPACK_SCALE` (`xasl_cache.c:316-324`, `UNPACK_SCALE 3` `src/query/xasl.h:59`).

### 1.5 unpack 의 실체와 arena

- `stx_map_stream_to_xasl` (`src/query/stream_to_xasl.c:212-283`): `stx_init_xasl_unpack_info` 가 `db_private_alloc(sizeof(XASL_UNPACK_INFO) + stream_size×3)` 한 덩어리를 잡고 (`src/xasl/xasl_stream.cpp:74-107`), 노드는 `stx_alloc_struct` 로 이 arena 를 bump-alloc (`:221-270`; 넘치면 추가 버퍼를 `additional_buffers` 로 추적). DB_VALUE 는 `or_unpack_db_value` 로 복원되며 문자열 payload 는 arena 가 아니라 `db_private_alloc(NULL, ...)` (`object_primitive.c` `mr_readval_string_internal` 내부) — 클론이면 위 `:1128` 에 의해 전역 heap. 해제는 `free_xasl_unpack_info` (`src/xasl/xasl_unpack_info.cpp:69`).
- 비-캐시 실행(`qmgr_process_query` `:1187`): `xasl_tree` 가 주어지면 그대로 쓰고 `:1220`, 아니면 stream 에서 unpack `:1224`, `set_xasl_unpack_info_ptr` `:1230`, `qexec_execute_query` `:1242`, 끝에 `free_xasl_unpack_info` `:1276`. **즉 `qmgr_process_query` 는 이미 in-memory XASL_NODE* 를 받는 시그니처를 갖는다**(후보 b 의 seam).
- 상태 전이 계약(`stream_to_xasl.c:1750-1763`): `XASL_BUILD → SUCCESS/FAILURE → INITIALIZED/CLEARED(qexec_clear_xasl)`; 캐시 재사용은 2·3 반복.
- 병렬 스캔 워커 (`src/query/parallel/px_scan/px_scan_task.cpp:570-611`): `m_uses_xasl_clone` 이면 xcache 에서 **자기 클론**을 하나 더 획득, 아니면 **메인 스레드의 `xasl_unpack_info_ptr->packed_xasl` 에서 재-unpack** `:595-598`. 워커당 독립 XASL 인스턴스가 전제이며, 그 복사 수단이 stream 이다.

### 1.6 폴드 diff (develop ↔ cas-merge)

| 파일 | 변경 | 내용 |
|---|---|---|
| `src/query/xasl_to_stream.c` | 49줄 | 정적 상태 `CSQL_PARSER_TLS`, `xts_debug_check` 가 실제 thread entry 사용 + 슬롯 save/restore (`:8045-8085`, 결함 5) |
| `src/query/stream_to_xasl.c`, `src/query/xasl_cache.c`, `src/xasl/xasl_stream.cpp`, `src/xasl/xasl_unpack_info.cpp` | 0줄 | — |
| `src/query/query_manager.c` | 121줄 | `xqmgr_execute_query`/`xqmgr_prepare_and_execute_query` 가 packed `void*` 대신 `DB_VALUE*`(borrowed) 를 받음(#124 D4); in-process method 재진입 매크로 |

`xts_debug_check` (`xasl_to_stream.c:8029-8087`) 는 `#if !defined(NDEBUG)` 전용이고 호출처는 json_table 5곳(`:5152,5179,5187,5224,5246`)뿐 — release 에는 왕복검증이 없다.

## 2. stream 을 유지해야 하는 이유(현재 코드 기준)

1. **와이어 포맷 소비자가 살아 있다.** libcubridcs 는 계속 빌드되고(`cs/CMakeLists.txt:629-642`), csql 은 `-C` 시 `LIB_UTIL_CS_NAME`(libcubridcs.so) 를 런타임 로드(`src/executables/csql_launcher.c:471`, `utility.h:1810`), cub_admin 유틸도 동일 로더. 브로커 바이너리 20종이 cubridcs 링크(`broker/CMakeLists.txt`). 서버 핸들러 `sqmgr_prepare_query`/`sqmgr_execute_query`/`sqmgr_prepare_and_execute_query` 존치(`src/communication/network_interface_sr.cpp:5402,5694,6363`). #126 은 HA 데몬 4종·유틸 채널 잔류를 확정했으므로 stream **포맷과 서버측 unpack 코드는 제거 대상이 아니다**. 논의 대상은 오직 "드라이버 세션의 in-process 경로가 stream 을 경유하느냐"다.
2. **디스크 영속 stream.** 필터 인덱스 술어·함수 인덱스 식은 `xts_map_filter_pred_to_stream`/`xts_map_func_pred_to_stream` 산출물이 카탈로그에 저장되고(`src/query/execute_schema.c:3431,15561,15940`) 서버가 `stx_map_stream_to_filter_pred/func_pred` 로 읽는다(`src/storage/btree_load.c:1029-1040,1219-1239,7374-7388`, `src/storage/heap_file.c:18112,18249`, `src/query/filter_pred_cache.c:409`, `src/query/partition.c:2890`). 같은 xts/stx 기계다.
3. **클론 = 깊은 복사 기계.** 실행은 XASL 을 가변 상태로 쓰기 때문에(§4 a 목록) 동시 실행마다 독립 인스턴스가 필요하다. 현재 그 인스턴스 생성 수단은 "stream 에서 unpack" 하나뿐이다(`xasl_cache.c:1133`, `px_scan_task.cpp:597`). XASL 트리를 포인터 재배치로 복사하는 코드는 없다.
4. **MOP-free 규약이 경계에서 공짜.** 컴파일러 산출 XASL 의 상수 DB_VALUE 에는 MOP(`DB_TYPE_OBJECT`) 가 들어갈 수 있다. pack(클라 모자) 이 OID 로 쓰고(`object_primitive.c:5222-5260`), unpack(서버 모자) 이 `DB_TYPE_OID` 로 읽는다(`:5298-5303`). in-memory 직결이면 이 정규화를 트리 전수 방문으로 따로 해야 한다(#124 D4 "OID 정규화는 호출자측" 이 host 변수에 대해서만 구현됨 `network_interface_cl.c:7772-7790`).
5. **메모리 소유 모델 불일치.** 컴파일러 XASL 은 parser 의 `regu_alloc` arena(파서 해제 시 소멸)이고 실행기는 unpack arena(`db_private_alloc`, 클론은 전역 heap) 를 전제로 `free_xasl_unpack_info` 로 통째 해제하며, `qexec_clear_xasl` 계열이 `pr_clear_value`·`free(p->parts)` 등 부분 해제를 수행한다(`src/query/query_executor.c:1486-1560`, `:1853-1900`). 실행기가 파서 arena 에 쓰고 일부를 free 하는 조합은 현재 어디에도 없다(SA 모드도 stream 경유 — `network_interface_cl.c:7489` 분기가 SA 공용).
6. **재컴파일 판정은 stream 무관.** 키 sha1 + `time_stored`, RT 임계(`xcache_check_recompilation_threshold` `:2659-2745`, 클래스 페이지수 10× 변화·10분 간격), DDL 무효화 `xcache_remove_by_oid` `:2074`, 클라이언트 재시도 `src/compat/db_vdb.c:2287-2300`·`execute_statement.c:15668`. chn 은 워크스페이스 재검증용(#123 D4)이며 xcache 는 클래스 락+삭제 마크로 유효성을 보장한다(#177 보충 Q&A). 헤더 플래그(`qfile_load_xasl_node_header`)만 stream 에서 읽으므로 stream 을 없애도 이 판정 로직은 그대로 쓸 수 있다 — 즉 "유지 이유"가 아니라 "제거해도 무관한 축".

## 3. 비용 근거

### 3.1 있는 것

- **YCSB 프로파일(#177 코멘트, 2026-09-01, threads=100, perf -F199 -g)**: C 상위 = glibc malloc 9.1%, `log_commit` 7.4%, `__memmove` 4.14%, `pthread_mutex_lock` 3.13%, 2PL 락 4.17%(그중 `xcache_find_xasl_id_for_execute` 의 클래스 IS 락 `xasl_cache.c:1061` 이 주). memmove 는 `cursor_open → pt_new_query_result_descriptor`(query_result.c:1067) 결과 디스크립터 복사로 귀속. **`xts_*`/`stx_*`/`or_pack_*` 는 top-25 에 부재** → 프리페어드 히트 정상상태에서 pack/unpack 이 핫스팟이 아님을 시사(클론 풀 히트 = §1.4 설명과 일치).
- **#125 베이스라인**: 클라이언트 컴파일 +380µs/문장(487 vs 103µs) — pack 이 아니라 파싱·최적화 전체. pack 의 몫은 분리 측정되지 않았다.
- **카운터**: `Num_plan_cache_add/lookup/hit/miss/full/delete/invalid_xasl_id/entries` (`src/base/perf_monitor.c:326-333`), `cubrid plandump`(`src/executables/util_cs.c:2197` → `xqmgr_dump_query_plans` `query_manager.c:2058` → `xcache_dump` `xasl_cache.c:2165`): lookups/hits/miss/inserts/found_at_insert/recompiles/failed_recompiles/deletes/fix/unfix/cleanups, 메모리(cache/clone), **엔트리별 Memory Usage(≈ stream 크기+텍스트, `xcache_entry_get_entrysize`)·Clone Memory Usage**. 시간 카운터·클론 미스 카운터는 없다.

### 3.2 없는 것 → 측정 방법 제안

1. **pack/unpack 시간 지분**: release 빌드에 `perf record -g --call-graph dwarf` 로 (i) YCSB C/A(프리페어드), (ii) 비-prepared 워크로드(csql/CTP sql 일부 — `prepare_and_execute` 경로) 두 레그. 심볼 필터 `xts_map_xasl_to_stream|stx_map_stream_to_xasl|or_pack_|or_unpack_|stx_restore_|xts_save_` 의 self+children 합. 기대: (i) ≈ 0, (ii) 가 실제 후보.
2. **클론 미스율**: 측정 브랜치에서 `xasl_cache.c:1103`(pop 성공)·`:1128`(미스→unpack) 에 `XCACHE_STAT_INC` 두 개 추가하고 plandump 로 읽기. 100 스레드가 한 플랜을 치면 풀 정상상태 = 최대 동시 실행 수(≤ `max_plan_cache_clones`), 이 값과 `Max_plan_size` 상한이 미스 원인.
3. **stream 크기 분포**: CTP sql/medium 완주 후 `cubrid plandump` 엔트리별 Memory Usage 히스토그램(stream 크기 ≈ Memory Usage − 텍스트 길이). YCSB 는 플랜 수개라 분포 의미 없음.
4. **seam 복사 비용**: `qmgr_prepare_query` 의 memcpy(`:7512`) 는 컴파일 미스에서만, `qmgr_attach_first_page_copy` 의 `DB_PAGESIZE` memcpy 는 **매 실행** — 후자가 XASL 과 무관하지만 memmove 지분 재귀속 시 함께 볼 것.

## 4. 대체 후보별 불변식·위험·seam

### 4.1 실행이 쓰는 가변 필드(공유 XASL 의 위험 목록)

| 구조체 | 실행 중 쓰기 | 근거 |
|---|---|---|
| `XASL_NODE` | `status`(BUILD/SUCCESS/FAILURE/INITIALIZED/CLEARED), `list_id`(결과 리스트 파일), `query_in_progress`, `next_scan_on/next_scan_block_on`, `curr_spec`, `px_executor`, `executed_parallelism`, `memoize_storage`, `orderby_stats/groupby_stats/xasl_stats`, `topn_items`, per-row 결과 DB_VALUE `instnum_val/save_instnum_val/ordbynum_val/level_val/isleaf_val/iscycle_val`, `single_tuple` | `src/query/xasl.h:1120-1240`; `query_executor.c:8044-8133`(curr_spec), `:8399-8404`(next_scan_on), `:16081,16950,17020,18240,18333`(status), `qexec_clear_xasl :2339`(px_executor delete, memoize clear, list_id clear) |
| `ACCESS_SPEC_TYPE` | `s_id`(SCAN_ID 통째 — 스캔 상태·통계·조인 값), `parts/curent/pruned`(파티션), `grouped_scan/fixed_scan/cached_scan`, `s_dbval`, `clear_value_at_clone_decache` | `xasl.h:1083-1108`; `qexec_clear_access_spec_list :1853-1960` |
| `REGU_VARIABLE` | `domain`(실행 중 해석 후 `original_domain` 으로 복원), `flags`(`FETCH_ALL_CONST` 등 fetch 가 set), `vfetch_to` 대상 DB_VALUE, `value.dbval`(inline), `value.dbvalptr`(상수; 클론 decache 시 `pr_clear_value`), `attr_descr.cache_dbvalp/cache_slot`, `arithptr->value`, `funcp->value`, `sp_ptr->value`, aggregate 누산기 | `src/query/regu_var.hpp:176-215`; `fetch.c:3833-3853,3967,4593`(domain), `:4115`(flags); `qexec_clear_regu_var :1486-1640` |

가변 상태가 불변 플랜과 **같은 구조체 안에 섞여** 있고, `qexec_clear_xasl` 가 "실행 후 초기 상태 복원" 계약(`xcache_retire_clone :2327` assert)으로 클론 재사용을 성립시킨다. 파티션 `parts` 는 `free()` 로 해제·재할당된다.

### 4.2 (a) xcache 에 공유 unpacked XASL + copy-on-execute

- 불변식: 공유 인스턴스는 read-only; 실행 인스턴스는 위 표의 모든 필드를 자기 것으로 가져야 함; 포인터 그래프(regu→xasl 역참조 `regu_variable_node::xasl`, `curr_spec→spec_list`, 술어→regu) 재배치 필요.
- 위험: (1) 표의 필드가 트리 전체에 산재 → "상태만 복사"는 plan/state 구조 분리라는 대규모 리팩토링. (2) unpack arena 는 연속 bump 버퍼지만 `additional_buffers` 와 DB_VALUE payload(heap) 가 있어 memcpy+상대 포인터 재배치가 성립하지 않음. (3) 병렬 워커·memoize·px_executor 가 XASL 필드를 소유. (4) 현행 클론 풀이 이미 "깊은 복사 캐시"이므로, 클론 히트 상태에서는 (a) 의 이득이 0 — 이득은 클론 미스 순간의 unpack 비용만.
- seam: `xasl_cache.c:1095-1133`(클론 획득), `xcache_retire_clone`, `qexec_clear_xasl` 계약. **판정 전 3.2-2 의 클론 미스율이 선행 데이터.**

### 4.3 (b) 컴파일 세션 == 실행 세션일 때 in-memory 직결(캐시 채우기용 stream 은 유지)

- 적용 범위 사실: prepare 와 execute 는 **별도 드라이버 요청**이고 요청↔워커 어피니티가 없다(#123 D3). 따라서 "같은 스레드가 컴파일하고 바로 실행"은 `prepare_and_execute_query` 경로(비-prepared 문장, `execute_statement.c` 15곳, `query_manager.c:1788`) 및 prepare 미스 직후 같은 요청 안에서 실행까지 가는 CAS 폴드 경로(`cas_execute.c:1142 db_compile_statement` → `:1186 db_execute_and_keep_statement`)에만 성립. prepared 히트 정상상태에는 해당 없음.
- 이미 있는 seam: `qmgr_process_query(thread_p, xasl_tree, NULL, 0, ...)` 가 XASL_NODE* 를 직접 받는다(`:1187`, `:1220`). `xqmgr_prepare_and_execute_query` 에 XASL_NODE* 오버로드를 두고 `qmgr_prepare_and_execute_query` SERVER_MODE 분기(`network_interface_cl.c:7920`)에서 넘기는 것이 최소 변경.
- 선결 불변식/위험: (1) **MOP 정규화** — 트리 안 모든 DB_VALUE(regu 상수, `s_dbval`, json_table default, 술어 상수 등)를 OID 로 바꾸는 방문자가 필요; 누락 시 서버 실행기가 MOP 포인터를 값으로 다룸(#123 D1 불변식 위반). (2) **arena 수명** — 컴파일러 트리는 parser arena; 실행기의 `free_xasl_unpack_info`·`pr_clear_value`·`free(parts)`·`qfile_clear_list_id` 가 그 위에서 동작해야 하고, `parser_free_parser` 이전에 실행이 끝나야 함(현재 `do_select` 류는 같은 함수 안에서 끝나므로 순서 자체는 만족). (3) **`thread_p->xasl_unpack_info_ptr` 소비자** — 병렬 스캔 워커가 `packed_xasl` 에서 재-unpack(`px_scan_task.cpp:597`) → in-memory 트리에는 packed 가 없어 병렬을 끄거나 워커용 stream 을 지연 생성해야 함. (4) 캐시 투입은 여전히 stream 이 필요하므로 pack 은 남고 **unpack 1회만 절약** — 이득 상한 = 비-prepared 문장의 unpack 시간(3.2-1 (ii) 레그).
- 되돌림: 오버로드 진입점 추가만이라 플래그/`#if` 로 격리 가능.

### 4.4 (c) debug pack/unpack 왕복검증 생략

- 사실: `xts_debug_check` 는 `!NDEBUG` 전용, json_table 5곳만(§1.6). release 비용 0. 결함 5 의 원인 지점이었고 폴드에서 thread 슬롯 save/restore 로 수정됨(`xasl_to_stream.c:8045-8085`).
- 판정: 성능 후보가 아니다. 남길 가치(json_table pack 크기 추정 검증)가 있어 유지 권고.

### 4.5 (d) stream 을 유지한 채 값싼 개선

1. **seam memcpy 제거**: `qmgr_prepare_query` SERVER_MODE 분기가 `xts` 의 malloc 버퍼를 다시 malloc+memcpy(`:7503-7512`). xcache 도 plain malloc 소유를 전제(`xcache_entry_uninit :615 free_and_init`)하므로 `server_stream.buffer = stream->buffer` 로 넘기고 `xqmgr_prepare_query` 후 `stream->buffer` 를 NULL 로 돌려주면 호출자(`execute_statement.c:15421` 류의 `free_and_init(stream.buffer)`)와 소유권이 맞는다. 컴파일 미스 시 1회, 크기 = stream 크기.
2. **클론 풀 튜닝·관측**: 3.2-2 카운터 추가 후 `max_plan_cache_clones`·`Max_plan_size`(대형 플랜은 클론 보관 거부 `:2332`) 점검.
3. **per-execute 클래스 IS 락**(`:1053-1075`)은 stream 과 무관하지만 #177 이 지목한 실측 비용 — 별도 티켓 사안.

## 5. 확인 못 한 것

- pack/unpack 의 실제 시간·stream 크기 분포: 측정 데이터 없음(3.2 방법만 제안). #177 프로파일 원자료 디렉터리(`.git_ignored_dir/scratch/ycsb-run/profile/20260901-195036/`, `reports/bottleneck-wf177.md`)는 이 호스트의 어느 워크트리에서도 발견되지 않아 top-25 부재는 코멘트 텍스트에 의존.
- YCSB JDBC 바인딩이 op 마다 prepare 를 다시 보내는지(드라이버측 statement pool 여부) — prepare 히트 경로 빈도의 전제. `cas_execute.c` 의 `is_prepared` 분기(`:1085-1142`)까지만 확인.
- 클론 풀 미스 빈도(100 스레드 × 1 플랜 정상상태에서 풀이 채워지는지, `Max_plan_size` 로 거부되는 플랜 비율).
- 4.1 표는 grep 기반 열거이며 전수는 아님(aggregate/analytic/hash join/CTE/connect-by 내부 상태, `memoize`, `px` 필드의 세부 쓰기 지점 미열거).
- `thread_p->xasl_unpack_info_ptr` 의 소비자 전수(병렬 워커 외 — method/SP 재진입 시 save/restore 요구가 결함 5 로 드러났듯 다른 소비자가 있을 수 있음).
- 컴파일러 XASL 의 정확한 할당자(`regu_alloc` → parser arena 라는 전제)와 `parser_free_parser` 시점 대비 실행 종료 순서의 전 경로 확인.
- SA 모드(cubridsa) 가 stream 을 우회하는 선례가 있는지 — `network_interface_cl.c:7489` 분기가 SA 공용이라 없다고 판단했으나 다른 SA 전용 진입점은 미조사.
