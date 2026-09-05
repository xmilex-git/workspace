# prepared statement / 실행계획의 세션 간 공유 가능성 — 사실 인벤토리

- 티켓: xmilex-git/workspace#212 (Part of #207) · 종류: research(AFK)
- 기준 코드: cas-merge tip `7117c8a66` (`/home/cubrid/dev/worktrees/wf143-gate`, == xmilex/cas-merge). 모든 `path:line`은 이 트리 기준.
- 비교 기준: upstream develop `6dbf6d92f` (`~/dev/cubrid`). 폴드 전용 변경은 merge-base `5ae45603f`와의 diff로 판정.
- 질문: **CAS 계층이 다중스레드 cub_server 안으로 폴드된 지금, prepared statement(핸들)와 실행계획을 세션(구 CAS) 간에 공유할 수 있는가?** 의견이 아닌 코드 사실을 모은다.

## 요약 표

| # | 사실 | 근거 |
|---|---|---|
| 1 | 폴드 후에도 **prepare/execute 경로 코드는 merge-base와 바이트 동일**. `ux_prepare`/`ux_execute`에 폴드 hunk 없음 → 세션마다 파싱·의미검사·XASL 생성이 그대로 반복된다. 폴드가 제거한 것은 프로세스 경계(IPC hop)이지 중복 컴파일이 아니다. | `git diff 5ae45603f..HEAD -- src/broker/cas_execute.c` hunk 목록(§3.5) |
| 2 | 핸들 풀(`srv_handle_table`)은 `CAS_TLS`(=`thread_local`) 정적 배열. 폴드 화자는 "접속당 전담 스레드 1개"이므로 스레드-로컬 = 세션-로컬. 공유 자료구조가 아니다. | `src/broker/cas_handle.c:52-58`, `src/broker/cas_common_vars.h:33-39`, `src/connection/adoption.cpp:516` |
| 3 | 핸들 하나(`T_SRV_HANDLE`)가 소유하는 것: SQL 원문, `DB_SESSION*`(=PARSER_CONTEXT+파스 트리+`xasl_id`+host var 도메인), `T_QUERY_RESULT`(컬럼 메타·커서·결과), autocommit/holdable/pooled 플래그. **파스 트리 안에 세션 워크스페이스의 MOP 포인터가 박혀 있다.** | `src/broker/cas_handle.h:119-165`, `src/compat/db_session.h:26-50`, `src/parser/parse_tree.h:2685-2686` |
| 4 | 서버 XASL 캐시(xcache)는 **이미 세션 간 공유**된다. 키 = `SHA1(alias_print)` 하나이고, alias_print에는 (a) 정규화 SQL, (b) `user=vol|page|slot`(현 사용자 OID), (c) `?`+플랜캐시 영향 시스템 파라미터 인쇄, (d) host var count가 포함된다. 엔트리는 **packed stream**을 저장하고 실행 시 스레드별 clone으로 unpack한다. | `src/query/execute_statement.c:113,15287-15293`, `src/parser/parse_tree_cl.c:3084-3110,3164`, `src/query/xasl_cache.c:872-891,1133`, `src/query/xasl_cache.h:91-129` |
| 5 | 따라서 폴드 세션 B가 세션 A와 같은 (SQL, user, 파라미터 세트)로 prepare하면 **XASL 생성은 건너뛴다**(xcache hit → `xasl_id`+header만 받음). 남는 것은 파싱·`pt_compile`(의미검사·권한·mq 변환)·alias_print 인쇄·SHA1. YCSB 실측의 +380µs/문장은 이 전체 컴파일 경로 비용이며, xcache hit 시 절감분과 잔여분은 **미분해(측정 없음)**. | `src/compat/db_vdb.c:970-984,1110`, `src/query/query_manager.c:1042-1071`, ycsb-baseline(§3.5) |
| 6 | 세션 간 핸들 공유를 막는 상태 9종을 §3.4 표로 열거: MOP 참조, 사용자 OID(권한·키), 세션-유효 시스템 파라미터(결함 10·11 선례), chn 기반 무효화, bind 값/도메인, 커서·결과, autocommit/holdable, query-info 재컴파일, bind-peek 리플랜 상태. | §3.4 |
| 7 | 권한: 컴파일 시 `au_fetch_class(..., AU_SELECT)`로 검사되고 XASL 자체에는 권한 검사가 없다. 폴드는 REVOKE에 `sm_touch_class`를 추가해 **타 세션의 prepared statement를 chn 범프+xcache 무효화로 강제 재컴파일**시킨다(결함 경로: wf171에서 drop 순서 수정). | `src/object/authenticate_grant.cpp:702-717`, `src/parser/name_resolution.c:8170,8231`, 커밋 `9a563c11a`·`7e59906e4` |
| 8 | **MOP 없는 서버 상주 prepared 서술자의 선례가 이미 있다**: SQL-level `PREPARE name FROM ...`는 세션 상태에 `{name, alias_print, sha1, packed prepare_info(컬럼·host var 도메인·stmt_type)}`만 남기고, EXECUTE는 xcache에서 sha1로 XASL을 다시 찾는다. 설계 후보 B의 골격에 해당. | `src/session/session.c:100-109,1779-1800,1891-1953`, `src/compat/db_vdb.c:2890-3000,3049-3103`, `src/compat/db_query.h:149-163` |

## 1. 범위와 방법

- 읽기 전용 조사. 빌드·실행 없음. cas-merge 트리와 develop 트리를 `git diff`/`git show`로만 비교.
- "레거시 CAS"는 브로커 프로세스 모델(1 CAS 프로세스 = 1 세션, 각 프로세스에 libcubridcs 클라이언트 반쪽 상주)을 뜻하고, "폴드"는 cas-merge에서 CAS 화자와 클라이언트 반쪽이 cub_server 프로세스 안 스레드로 들어온 상태를 뜻한다.
- 인용 문서: `docs/research/ycsb-baseline.md`는 현재 main 트리에 없고 git 히스토리(커밋 `b7bf65b`)에만 있다. `client-global-state.md`(커밋 `20d1c84`·`bfc594e`), `sa-mode-merge-boundary.md`(커밋 `e674aee`)도 동일. 본문은 `git show <commit>:docs/research/<file>`로 읽었다.

## 2. 구조 개요 (폴드 기준)

```
driver thread (adoption.cpp:516 std::thread → driver_session_run)
 └ client_session_context ctx = new; csc_activate(ctx)        driver_session.cpp:551-552
   └ session_adopt_client_context(entry, ctx)                  driver_session.cpp:696 / session.c:2934
   └ loop: cas_process_request(fd, …)                          driver_session.cpp:464
       └ fn_prepare → ux_prepare                               cas_execute.c:681
            hm_new_srv_handle (CAS_TLS srv_handle_table)       cas_handle.c:61,52
            db_open_buffer → db_compile_statement              cas_execute.c:816,839
              pt_class_pre_fetch → pt_compile → do_prepare_statement
              → do_prepare_select: alias_print+SHA1 → prepare_query(NET) → xqmgr_prepare_query
                 xcache_find_sha1 hit  → xasl_id 반환 (XASL 생성 생략)
                 miss → parser_generate_xasl → xts_map_xasl_to_stream → xcache_insert
       └ fn_execute → ux_execute → db_execute_and_keep_statement → execute_query(xasl_id)
            서버: xcache_find_xasl_id_for_execute → clone unpack → 실행
```

폴드에서 "세션"은 세 층으로 나뉜다. (1) 서버 `session_state`(`session.c:124`, `csc_p` 포인터 `:157`), (2) 클라이언트 반쪽 `client_session_context`(워크스페이스·권한·스키마 매니저·트랜잭션 상태; `client_session_context.hpp:61-165`), (3) CAS 화자의 `CAS_TLS` 전역(핸들 풀 등). 핸들은 (3)에 살고 그 내용물(DB_SESSION)은 (2)의 워크스페이스에 묶인다.

## 3. 사실 인벤토리

### 3.1 핸들 풀과 핸들 하나의 소유물

**풀 자체.**

- `srv_handle_table`, `max_srv_handle`, `max_handle_id`, `current_handle_count`, `current_handle_id`가 모두 `static CAS_TLS` — `src/broker/cas_handle.c:52-58`. develop은 `static`(프로세스 전역) — 폴드 diff에서 `CAS_TLS` 접두만 추가됨(`git diff 5ae45603f..HEAD -- src/broker/cas_handle.c`, 19줄).
- `CAS_TLS`의 정의와 근거: "merged server에서 CAS 화자는 adopted connection당 전담 스레드 1개로 돌므로 CAS-프로세스-전역을 스레드-로컬로 만들어 세션-로컬화" — `src/broker/cas_common_vars.h:33-39`. 스레드 생성: `src/connection/adoption.cpp:516,645` (`std::thread session_thread (driver_session_run, …)`).
- 핸들 ID는 1-base 인덱스(`hm_find_srv_handle`, `cas_handle.c:137-144`). 즉 **핸들 ID는 스레드(세션) 내에서만 의미가 있다**. 다른 세션의 ID를 받아도 자기 테이블을 본다.
- 접속 종료 시 statement pooling이면 전부 해제: `src/connection/driver_session.cpp:468-470` (`hm_srv_handle_free_all (true)`); 레거시 루프의 대응 위치는 `src/broker/cas.c:566-568`.
- `is_pooled`는 생성 시 `as_info->cur_statement_pooling`(`cas_handle.c:112`)과 실행 후(`src/broker/cas_function.c:631-635`)에 세팅되고, 실행이 `ER_QPROC_INVALID_XASLNODE`/`ER_HEAP_UNKNOWN_OBJECT`로 실패하면 `CAS_ER_STMT_POOLING`으로 바꿔 드라이버에게 재-prepare를 시킨다(`cas_execute.c:1218-1222`). 즉 **재컴파일 결정의 최종 주체는 드라이버(JDBC statement pool)** 이다.

**핸들 하나(`T_SRV_HANDLE`, `src/broker/cas_handle.h:119-165`)가 소유하는 것.**

| 필드 | 내용 | 세션 종속성 |
|---|---|---|
| `sql_stmt` (`:124`) | SQL 원문 복사본(`cas_execute.c:714`) | 없음 |
| `session` (`:120`) | `DB_SESSION*` — `PARSER_CONTEXT`, 컴파일된 `PT_NODE **statements`, `type_list`, `stage` (`src/compat/db_session.h:26-50`) | **강함** (아래) |
| `q_result` (`:122`) → `T_QUERY_RESULT` (`:72-86`) | `stmt_id`, `stmt_type`, `column_info`(DB_QUERY_TYPE 리스트), `col_update_info`(class/attr 이름), `null_type_column`, `result`(DB_QUERY_RESULT), `tuple_count`, `is_holdable` | prepare 시점엔 메타만(`cas_execute.c:6704` 컬럼 리스트를 네트 버퍼로 직렬화), 실행 후엔 결과·커서 |
| `num_markers` (`:130`) | `?` 개수 | 없음 |
| `prepare_flag`, `is_prepared`, `is_updatable`, `query_info_flag` (`:139-142`) | CCI prepare 플래그, 컴파일 성공 여부, updatable 커서, plan-dump 요청 | 접속별 옵션 |
| `is_pooled`, `need_force_commit`, `auto_commit_mode`, `forward_only_cursor` (`:143-146`) | 풀링·autocommit·커서 방향 | **트랜잭션/접속 속성** |
| `use_plan_cache`, `use_query_cache` (`:147-148`) | 마지막 prepare/execute가 xcache/결과 캐시를 탔는지(`db_get_cacheinfo`, `cas_execute.c:910`) | 로그용 |
| `is_holdable`, `is_from_current_transaction` (`:150-151`) | 커밋 후 커서 유지 | **트랜잭션 속성** |
| `classes`, `classes_chn` (`:125-126`) | 해제만 됨(`cas_handle.c:167`), `check_class_chn`은 `0`으로 매크로 치환(`cas_execute.c:282`) | 죽은 필드 |

**`DB_SESSION`(핸들→`session`)이 끌고 다니는 것.**

- `parser->host_variables`, `host_var_expected_domains`, `host_var_count`, `auto_param_count` — `src/parser/parse_tree.h:3904-3908`. 바인드는 `set_host_variables → db_push_values → pt_set_host_variables`(`cas_execute.c:10171-10177`, `db_vdb.c:1911`, `parse_dbi.c:3072`)로 **기대 도메인에 캐스트되어 파서에 저장**된다(`parse_dbi.c:3110,3119`).
- `statement->xasl_id`(`parse_tree.h:3769`)와 `parser->context`(`COMPILE_CONTEXT`, `:3938`; 구조 `src/xasl/compile_context.h:37-52`: `sql_user_text`, `sql_hash_text`, `sha1`, `recompile_xasl` 등).
- 파스 트리의 클래스 참조: `pt_name_info.db_object`(MOP)와 `db_object_chn` — `src/parser/parse_tree.h:2685-2686`. chn은 `pt_class_pre_fetch`에서 채워진다(`src/parser/compile.c:647`).
- 컬럼 헤더 `type_list`(`db_session.h:34`), SQL-level PREPARE용 `kept_trees`/`kept_stmt_name`(`:42-45`; develop에도 존재, 폴드 전용 아님).
- 해제: `db_close_session_local`이 kept tree·sub-session·`type_list`·`xasl_id`·파서를 순서대로 푼다(`src/compat/db_vdb.c:4273-4343`). `hm_session_free`가 이를 호출(`cas_handle.c:359-366`).

### 3.2 컴파일 경로: 세션마다 무엇을 하는가

`db_compile_statement_local`(`src/compat/db_vdb.c:826`):

1. 파싱(`db_open_buffer`, `:500`) → `pt_class_pre_fetch`(클래스 MOP fetch + 락 + chn 기록, `:970`, `compile.c:647`) → `pt_compile`(의미검사·이름해석·권한·뷰 변환, `:984`).
2. `PRM_ID_XASL_CACHE_MAX_ENTRIES > 0 && !cannot_prepare`면 `do_prepare_statement`(`:1089-1110`) → SELECT는 `do_prepare_select`(`execute_statement.c:15240`).
3. `do_prepare_select`: alias_print 인쇄(`:15287-15288`, 플래그 `CUSTOM_PRINT_4_SHA_COMPUTE | PT_PRINT_DIFFERENT_SYSTEM_PARAMETERS | PT_PRINT_LOWER`) → `SHA1Compute`(`:15291-15293`) → **stream 없이** `prepare_query`(`:15312`, `query_cl.c:53-74`) → 서버 `xqmgr_prepare_query`가 `xcache_find_sha1(FOR_PREPARE)`(`query_manager.c:1042`).
   - hit: `xasl_id`와 요청 시 XASL header를 돌려주고 끝(`:1066-1071`). 클라이언트는 header 플래그로 LIKE/LIMIT 재최적화·bind-peek 필요 여부만 판단(`execute_statement.c:15326-15351`).
   - miss: 클라이언트가 `parser_generate_xasl`(`:15365`) → `xts_map_xasl_to_stream`(`:15380`) → stream을 실어 다시 `prepare_query`(`:15408`) → `xcache_insert`(`query_manager.c:1126`).

즉 **폴드 세션 B의 prepare는 1·2·3의 파싱/의미검사/인쇄/SHA1까지는 항상 수행하고, XASL 생성·직렬화만 xcache hit로 생략**한다. 이것은 develop과 동일한 동작이고 폴드가 바꾼 바 없다.

### 3.3 서버 XASL 캐시(xcache)

**키.** 해시맵 조회 키는 `XASL_ID.sha1`만 사용(`src/query/xasl_cache.c:889-891`, `XASL_ID` 정의 `src/storage/storage_common.h:917-923`). sha1의 입력 `alias_print`는 `parser_print_tree`(`src/parser/parse_tree_cl.c:3068`)가 만들며 다음을 덧붙인다.

| 성분 | 코드 | 비고 |
|---|---|---|
| 정규화된 SQL(소문자·범위 변환·따옴표) | `execute_statement.c:113` `CUSTOM_PRINT_4_SHA_COMPUTE` | |
| `?` + 플랜캐시 영향 파라미터 인쇄 | `parse_tree_cl.c:3084-3088` → `sysprm_print_parameters_for_qry_string` (`system_parameter.c:12472`) | `PRM_FOR_QRY_STRING` 파라미터: `require_like_escape_character`(`:2044`), `return_null_on_function_errors`(`:2101`), `oracle_style_empty_string`(`:2170`), `multi_range_opt_limit`(`:3267`), `intl_number_lang`(`:3278`), `intl_date_lang`(`:3289`), `sort_limit_max_count`(`:3450`), `max_hash_list_scan_size`(`:3579`), `timezone`(`:3918`), `memoize_memory_limit`(`:5380`), 조건부 `tz_leap_second_support`(`:10685,10772`) |
| `user=vol|page|slot` (현재 사용자 OID) | `parse_tree_cl.c:3091-3097`, `parser_print_user` `:3164` (`ws_identifier (db_get_user ())`) | **사용자별로 키가 다르다** → 같은 SQL이라도 사용자마다 별개 플랜 |
| host var count(캐시 힌트 서브쿼리 한정) | `parse_tree_cl.c:3099-3110` | |

`xasl->creator_oid`도 stream에 패킹되고(`src/query/xasl_to_stream.c:341`) 서버가 언팩하지만(`query_manager.c:1091`) **매칭에는 쓰이지 않는다**(사용자 구분은 위의 `user=` 문자열로만).

**폴드 전용 수정(결함 10·11).** `sysprm_print_parameters_for_qry_string`의 SERVER_MODE 분기가 `prm->value`(프로세스 전역) 대신 세션 read-through 값(`session_get_session_parameter`)을 인쇄한다 — `src/base/system_parameter.c:12484-12500`, 매크로 `PRM_SESSION_READTHROUGH` `system_parameter.h:738`. develop의 같은 함수에는 `SERVER_MODE` 분기가 없다(`git show 6dbf6d92f:src/base/system_parameter.c`). 근인·물증은 `docs/research/cas-merge-final-gate-and-defect-log-1.md:301-305`(PR cubrid#247): 레거시 CAS는 프로세스 prm이 곧 세션 유효값이어서 정상이었고, 폴드에서 세션 SET이 세션 스토리지로 가자 전 세션이 같은 키를 만들어 `intl_date_lang`/`timezone`이 다른 세션의 플랜이 별칭화됐다.

**엔트리(`XASL_CACHE_ENTRY`, `src/query/xasl_cache.h:91-129`).**

- `xasl_id`(sha1 + `time_stored`), `stream`(**packed XASL**, `:95`), `sql_info`(hash text·user text·plan text 복사, `:104`; 복사 `xasl_cache.c:1536`), `related_objects`(참조 클래스/시리얼 OID + 락 + tcard, `:106-111`; 채움 `xasl_cache.c:1512`), 참조 카운트·마지막 사용 시각·RT 체크 시각, **clone 풀**(`cache_clones`, `one_clone`, `:120-125`).
- 파스 트리·컬럼 메타·host var 도메인은 **저장하지 않는다**. 실행 시 `xcache_find_xasl_id_for_execute`(`:969`)가 sha1로 찾고 `time_stored`가 다르면 거부(`:1002-1010`), 관련 클래스 전부에 락을 잡아 유효성을 확인(`:1047-1050`), clone 풀에서 unpack된 XASL을 꺼내거나(`:1104-1122`) `stx_map_stream_to_xasl`로 새로 unpack(`:1133`; clone 활성 시 전역 힙 사용 `:1130`). clone 수 상한은 `max_plan_cache_clones`(`xasl_cache.c:332`, `system_parameter.c:337`).
- 무효화: 클래스 갱신(`src/transaction/locator_sr.c:5672-5675`, 함수 `locator_update_force` `:5396`), 시리얼(`src/query/serial.c:1639`), 로그 복구(`src/transaction/log_manager.c:5143`)가 `xcache_remove_by_oid`(`xasl_cache.c:2074`)를 호출. 통계 임계 재컴파일은 `xcache_check_recompilation_threshold`(`:2659`)와 `XCACHE_ENTRY_RECOMPILED_REQUESTED` 플래그(`:916-925`).

**클라이언트 측 무효화 감지.** `db_execute_and_keep_statement_local`(`db_vdb.c:2007`)은 실행 전 `pt_has_modified_class`(`:2224`, 정의 `:4959-5041`)로 파스 트리의 각 클래스 MOP에 대해 `decached`(`:5004-5007`), `au_fetch_class_force`의 `ER_HEAP_UNKNOWN_OBJECT`(`:5011-5017`), **chn 비교**(`:5037-5041`)를 수행하고, 서버가 `ER_QPROC_XASLNODE_RECOMPILE_REQUESTED`/`ER_QPROC_INVALID_XASLNODE`를 돌려주면 `xasl_id`를 버리고 `do_prepare_statement`부터 재시도한다(`:2287-2320`). 이 검사는 **세션 워크스페이스의 MOP와 chn을 전제**한다.

### 3.4 세션 간 핸들 공유를 막는 상태 (열거)

| # | 상태 | 어디에 있나 | 왜 막는가 | 근거 |
|---|---|---|---|---|
| S1 | 파스 트리의 MOP 포인터 (`pt_name_info.db_object`, `virt_object`, spec `flat_entity_list`) | `DB_SESSION → parser → statements` | MOP는 `client_session_context.ws`(`ws_context.mop_table`)에 속한 세션 소유 객체. 다른 세션의 워크스페이스에서 역참조하면 무효 포인터/UAF. 폴드 주석이 같은 이유로 도메인 캐시도 세션별로 분리했음(`tp_domains`). | `parse_tree.h:2685-2687`, `client_session_context.hpp:72`, `work_space.h:464-478`, `client_session_context.hpp:125-133` |
| S2 | chn 기반 스키마 변경 감지 | `pt_name_info.db_object_chn` + `locator_get_cache_coherency_number(MOP)` | S1의 MOP를 통해서만 동작. 공유 핸들이면 "누구의 MOP로 비교하나"가 정의되지 않음. | `compile.c:647`, `db_vdb.c:4995-5041` |
| S3 | 현재 사용자(권한) | `client_session_context.au_context.current_user`(MOP) | 컴파일 시 `au_fetch_class(.., AU_SELECT)`로 권한 검사(이름해석·의미검사·XASL 생성). XASL/xcache에는 권한 검사가 없음. 플랜캐시 키도 `user=` OID 포함. REVOKE는 폴드 전용으로 `sm_touch_class`를 추가해 **타 세션 prepared 문장을 chn 범프+xcache 무효화로 재컴파일**시키는데, 이 메커니즘 자체가 "세션마다 자기 핸들을 재컴파일한다"를 전제. 부작용 선례: drop 경로에서 mid-drop 클래스 touch → wf171 순서 수정. | `authenticate_context.hpp:129`, `name_resolution.c:8170,8231`, `semantic_check.c:6076,6129,6626,6726`, `xasl_generation.c:2229,18900`, `authenticate_grant.cpp:702-717`, 커밋 `9a563c11a`, `7e59906e4` |
| S4 | 세션-유효 시스템 파라미터 | 서버 세션 스토리지(read-through) | 플랜 자체에 파라미터가 구워짐(요일명 lang, tz 접기 등). 키에 인쇄되므로 xcache 차원은 해결(결함 10), 그러나 **파스 트리/컬럼 메타 차원은 키가 없다** — `intl_date_lang` 등이 다른 세션이 같은 파스 트리를 쓰면 같은 결함이 재발. `qo_optimization_level`도 세션 override 슬롯. | `system_parameter.c:12484-12500`, defect-log `:301-305`, `client_session_context.hpp:139` |
| S5 | 바인드 값·기대 도메인 | `parser->host_variables`, `host_var_expected_domains` | 실행 직전 값이 파서에 캐스트 저장됨. 공유 시 동시 실행 레이스. 도메인 포인터는 `tp_domains`가 세션별인 타입(MOP 포함 도메인)에서 세션 소유. | `parse_tree.h:3904-3908`, `parse_dbi.c:3110-3119`, `db_vdb.c:3215` |
| S6 | 커서·결과 집합 | `T_QUERY_RESULT.result`, `tuple_count`, `cur_result`, `cursor_pos` | 트랜잭션·접속 소유. | `cas_handle.h:72-86,123,131` |
| S7 | autocommit / holdable / from-current-transaction / forward-only | `T_SRV_HANDLE` 플래그 → `db_set_statement_auto_commit`, `db_session_set_holdable` | 실행 시 DB_SESSION에 주입되는 접속별 속성. | `cas_handle.h:145-151`, `cas_execute.c:1165,1178` |
| S8 | query-info 재컴파일 상태 | `is_prepared=FALSE` + `recompile` + `set_optimization_level(514)` | 플랜 덤프 요청이 핸들을 미컴파일 상태로 되돌린다(같은 핸들 재사용을 다른 세션이 하면 상태 충돌). | `cas_execute.c:1071-1080,1148-1153` |
| S9 | bind-peek 리플랜 상태 | `statement->flag.hv_pred_plan_unpeeked`, `db_stmt_bind_fp_ptr`(히스토그램 fingerprint), `kept_trees` | 첫 실행/값 분포 변화 시 **보존한 post-transform 트리로 XASL만 재생성**. 세션별 바인드 값에 의존. (develop에도 존재; 폴드 전용 아님) | `db_vdb.c:2249-2283,166,3507`, `execute_statement.c:15345-15351`, `histogram_cl.cpp:2847` |

이 중 xcache가 **이미 해결한** 것은 S3(키에 user)·S4(키에 세션-유효 파라미터)·S2/S3의 서버측 무효화(related_objects + `xcache_remove_by_oid`)이고, S1·S5·S6·S7·S8·S9는 **핸들/DB_SESSION 층**의 문제다.

### 3.5 중복 컴파일 비용: 레거시 vs 폴드

**실측 인용** (`docs/research/ycsb-baseline.md` @ `b7bf65b`, 단일 스레드 PK SELECT, localhost):

| 경로 | mean | 근거 줄 |
|---|---|---|
| 직결 1-hop, `db_execute_and_keep_statement` 재사용 | ≈103µs | `:44` |
| CCI 2-hop(→CAS→server) | ≈134µs (hop ≈ +31µs) | `:45,51` |
| 직결 1-hop, **매회 재컴파일** | ≈487µs | `:47` |
| → 클라이언트측 SQL 컴파일 ≈ **+380µs/문장** (4.7×) | | `:53` |

같은 문서 `:59-62`: `db_execute_statement`는 컴파일된 문장의 재실행을 거부하고, 재실행은 CAS가 쓰는 `db_execute_and_keep_statement`(`cas_execute.c:1186`) 경로만 가능하다.

**레거시 모델에서 중복이 생기는 이유.** 컴파일 산출물(파스 트리·xasl_id·컬럼 메타·도메인)이 CAS 프로세스 주소공간의 `srv_handle_table`(프로세스 전역 static)에 있다. N개 CAS가 같은 SQL을 다루면 N번 컴파일(파싱~XASL 생성; XASL 생성은 xcache hit이면 생략)하고, JDBC statement pool은 CAS 단위로만 재사용된다.

**폴드가 이미 바꾼 것 / 남은 것.**

| 항목 | 폴드 후 | 근거 |
|---|---|---|
| prepare/execute 경로 코드 | **불변**. `git diff 5ae45603f..HEAD -- src/broker/cas_execute.c`의 hunk는 `:68-84`(include), `:328`(fetch table), `:541-606`(접속/기본설정, 세션 부트), `:6808`(컬럼 메타 문자열), `:9691-9777`(로그/autocommit). `ux_prepare`(681-935)·`ux_execute`(1055-1365)에 hunk 없음. | 위 diff |
| 핸들 풀 | 프로세스 전역 → `CAS_TLS`. 세션-로컬 그대로. | `cas_handle.c:52-58` |
| prepare_query / execute_query의 IPC | 프로세스 간 소켓 왕복 → 같은 프로세스 내 호출. hop 비용(+31µs 급) 제거. | (경로 미추적, §5) |
| xcache | 공유 상태 그대로. 키에 세션-유효 파라미터 인쇄만 수정. | `system_parameter.c:12484-12500` |
| 파싱·의미검사·인쇄·SHA1 | **세션마다 반복**. xcache hit이어도 수행. | `db_vdb.c:970-984`, `execute_statement.c:15287-15312` |
| 컬럼 메타 | 세션마다 `db_get_query_type_list`로 재생성·직렬화. | `cas_execute.c:6704` |

+380µs 중 "xcache hit으로 이미 절감되는 XASL 생성·직렬화"와 "잔여(파싱·의미검사·인쇄·SHA1·컬럼 메타)"의 분해 측정은 없다(§5).

### 3.6 선례: SQL-level PREPARE/EXECUTE의 서버 상주 서술자

`PREPARE name FROM '...'`는 다음을 만든다.

- 클라이언트 반쪽(`do_process_prepare_statement`, `db_vdb.c:2890`): 컴파일 후 `prepare_info = {columns=type_list[0], host_variables, host_var_expected_domains, stmt_type, …}`(`:2956-2964`, 구조 `db_query.h:149-163`)를 `db_pack_prepare_info`로 직렬화(`:2992`) → `csession_create_prepared_statement(name, alias_print, info)`(`:3000`).
- 서버 세션 상태(`session.c:100-109`): `PREPARED_STATEMENT {name, alias_print, sha1, info}`만 보관(`:1779-1800`). MOP·파스 트리 없음.
- EXECUTE(`do_get_prepared_statement_info`, `db_vdb.c:3049`): 서버에서 `{xasl_id, info, xasl_header}`를 받아(`:3067`; 서버는 `xcache_find_sha1(GENERIC)` `session.c:1953`) 컬럼·host var 도메인을 unpack하고(`:3073-3086`) `PT_EXECUTE_PREPARE` 노드에 `xasl_id`를 심는다(`:3103`). xcache에서 빠졌으면 `do_recompile_and_execute_prepared_statement`(`:3667`)로 원문 재컴파일.

이 경로가 보여주는 것: **"파스 트리 없이 (sha1 → xcache XASL) + (packed 컬럼 메타 + host var 도메인)"만으로 실행 가능한 서술자**가 이미 존재하고 세션 상태(서버)에 산다. 다만 (a) 세션 스코프(세션 간 공유 아님), (b) 재컴파일 시 원문을 다시 컴파일, (c) bind-peek 리플랜은 `kept_trees`(파스 트리 보존)에 의존 — 즉 트리를 완전히 버리지는 못했다.

## 4. 공유 설계 후보와 불변식

세 후보를 "무엇을 공유하는가"로 구분한다. 표의 불변식은 §3.4의 S1~S9를 근거로 도출했고, 각 항목은 코드 이음새(seam)를 함께 적는다. 이 절은 설계 스케치이며 구현 판단은 아니다.

### A. XASL만 공유 (현행 xcache 유지, 핸들 공유 없음)

현 상태. 세션마다 핸들·파스 트리·컬럼 메타를 갖고 XASL만 xcache로 공유.

| 불변식 | 현재 충족 여부 | 이음새 |
|---|---|---|
| A1. 키가 플랜에 구워지는 모든 세션-유효 입력을 담는다 (user OID, `PRM_FOR_QRY_STRING` 파라미터, host var count) | 충족(결함 10 수정 후). 단 `PRM_FOR_QRY_STRING` 목록이 완전한지는 별도 검증 필요(§5) | `parse_tree_cl.c:3084-3110`, `system_parameter.c:12484-12500` |
| A2. 참조 객체 변경 시 엔트리 무효화 | 충족(`related_objects` + `xcache_remove_by_oid`; REVOKE는 `sm_touch_class`) | `locator_sr.c:5672-5675`, `authenticate_grant.cpp:704-717` |
| A3. 실행 스레드는 공유 stream을 자기 clone으로 unpack해 쓴다(공유 가변 상태 없음) | 충족 | `xasl_cache.c:1104-1133` |

비용 프로필: 세션마다 파싱·`pt_compile`·인쇄·SHA1·컬럼 메타 반복(§3.5). 잔여 비용 절감 없음. 잔여 최적화 여지는 "네트 왕복 제거 후 `prepare_query`의 함수 호출화" 수준(§5).

### B. 파스 트리 없는 공유 서술자 (sha1 → XASL) + 컬럼 메타 + bind 도메인 공유

§3.6의 SQL-level PREPARE 서술자를 **세션 스코프에서 프로세스 스코프**로 올리고 키를 xcache와 같은 sha1(= user·파라미터 포함)로 삼는다. 세션 핸들은 `{서술자 참조, 자기 bind 값, 자기 커서/결과, 자기 플래그}`만 소유.

| 불변식 | 현재 상태 | 이음새 |
|---|---|---|
| B1. 서술자에 **MOP·워크스페이스 포인터가 없다** (컬럼 메타·도메인은 packed/값 복사; 도메인은 MOP 비포함 타입만 캐시 가능하거나 세션별 재구성) | `db_pack_prepare_info`는 이미 값 직렬화. `TP_DOMAIN*`은 MOP 포함 타입이 세션별(`tp_domains`) — 공유 시 도메인을 직렬화/재구성해야 함 | `db_vdb.c:2992`, `db_query.h:149-163`, `client_session_context.hpp:125-133` |
| B2. 서술자 키 = xcache 키(sha1). user·세션-유효 파라미터가 다르면 다른 서술자 | xcache 키 규칙 재사용 가능. 단 컬럼 메타에 파라미터 의존 성분(예: 컬럼 이름 대소문자, 타입 표시)이 있는지 검증 필요 | `execute_statement.c:15287-15293` |
| B3. 첫 prepare(서술자 생성)는 컴파일이 필요하고, 그 컴파일은 **어느 한 세션의 워크스페이스·권한** 아래에서 일어난다. 재사용 세션은 같은 user OID여야 권한 등가성이 보장된다(키에 user 포함으로 충족) | `au_fetch_class(AU_SELECT)`가 컴파일 시 검사 → 같은 user 키면 등가 | `name_resolution.c:8170,8231` |
| B4. 무효화: xcache 엔트리가 죽으면 서술자도 죽어야 하고(또는 sha1 재조회로 miss 감지), 재컴파일은 **어떤 세션이든 자기 워크스페이스로** 수행 후 서술자 갱신 | SQL-level PREPARE는 `do_recompile_and_execute_prepared_statement`로 세션이 재컴파일. 프로세스 스코프면 갱신의 원자성·경쟁(두 세션 동시 재컴파일) 규칙 필요 | `db_vdb.c:3667`, `xasl_cache.c:1002-1010`(time_stored 불일치) |
| B5. 클라이언트측 chn 검사(`pt_has_modified_class`)의 대체: 서술자에는 MOP가 없으므로 서버측 `related_objects` 락·검증(`xcache_find_xasl_id_for_execute`)만으로 충분함을 증명하거나, 서술자에 클래스 OID+chn 스냅샷을 두고 서버에 묻는 경로를 추가 | 현행 SQL-level EXECUTE는 이미 chn 검사 없이 xcache 검증에 의존(`PT_EXECUTE_PREPARE` 경로) — 등가성 확인 필요(§5) | `db_vdb.c:2224`, `xasl_cache.c:1047-1090` |
| B6. bind-peek 리플랜(S9)은 파스 트리가 필요 → 서술자에 트리가 없으면 (a) 리플랜을 원문 재컴파일로 대체하거나 (b) 트리 보존을 세션-로컬 부가물로 남김 | SQL-level PREPARE도 `kept_trees`로 트리를 남김 — 완전 무트리는 미달성 | `db_vdb.c:2249-2283,347` |
| B7. 서술자의 세션 종속 실행 속성(autocommit·holdable·updatable·include_oid)은 핸들에만 있고 서술자에는 없다. 단 `include_oid`/updatable은 컴파일 산출(컬럼 리스트에 OID 포함)에 영향 → 키 또는 서술자 변형이 필요 | `db_include_oid`가 컴파일 전에 파서 플래그 설정 | `cas_execute.c:828-831`, `db_vdb.c:1892` |

비용 프로필: 재사용 세션은 파싱·의미검사·인쇄·SHA1·컬럼 메타 생성을 건너뛴다(원문 → sha1을 얻는 최소 정규화는 필요; 원문 문자열 자체를 1차 키로 쓰는 전단 캐시가 있어야 파싱을 피할 수 있음 — 파싱 없이 alias_print를 만들 수 없기 때문).

### C. 핸들(파스 트리 포함) 전체 공유

`T_SRV_HANDLE`/`DB_SESSION`을 세션 간 공유.

| 불변식 | 현재 상태 | 이음새 |
|---|---|---|
| C1. 파스 트리의 MOP 포인터가 모든 세션에서 유효 | **불충족**. MOP는 세션 워크스페이스 소유(`ws_context.mop_table`). 공유하려면 트리를 MOP 대신 OID/이름으로 재작성하고 모든 소비자(`pt_has_modified_class`, `au_fetch_class`, `ws_identifier`)를 바꿔야 함 | `parse_tree.h:2685`, `work_space.h:464-478`, `db_vdb.c:4997` |
| C2. 파서에 실행별 가변 상태가 없다 | **불충족**. `host_variables`(bind 값), `query_id`, `flag.set_host_var`, `recompile`, bind-peek fingerprint가 파서/statement에 있음 → 동시 실행 레이스 | `parse_tree.h:3903-3908`, `db_vdb.c:2249-2283` |
| C3. 컴파일 시점 권한·세션-유효 파라미터가 재사용 세션과 동일 | 키에 user·파라미터를 넣으면 등가(B2·B3와 동일) | 위와 같음 |
| C4. 핸들의 커서/결과/플래그(S6·S7·S8)는 공유 대상에서 분리 | 현재 한 구조체에 혼재 → 구조 분할 필요 | `cas_handle.h:119-165` |
| C5. 동시 접근 직렬화 | 현재 `bracket_mutex`는 세션 단위(다른 세션의 컨텍스트를 보호하지 않음) | `client_session_context.hpp:67` |

C는 C1·C2 때문에 "파스 트리를 워크스페이스-무관·불변으로 만드는 대규모 재작성"과 등가다. B는 그 재작성을 회피하고 이미 존재하는 서술자 직렬화 형식을 승격한다.

### 후보 비교 (사실 기반)

| | A (현행) | B (무트리 서술자 공유) | C (전체 핸들 공유) |
|---|---|---|---|
| 재사용 세션이 건너뛰는 것 | XASL 생성·직렬화 | + 파싱·의미검사·인쇄·SHA1·컬럼 메타 | (B와 동일) |
| 새로 필요한 불변식 | 없음 | B1~B7 | C1~C5 (+B의 대부분) |
| 기존 선례 | xcache | SQL-level PREPARE 서술자(§3.6) | 없음 |
| 가장 무거운 이음새 | — | 도메인 직렬화(B1), chn 검사 대체 증명(B5), bind-peek(B6) | 파스 트리 MOP 제거(C1) |

## 5. 확인 못 한 것

1. **+380µs의 분해.** xcache hit 시 절감되는 XASL 생성·직렬화 대비 잔여(파싱·`pt_compile`·인쇄·SHA1·컬럼 메타) 비율은 측정하지 않았다. 폴드 빌드에서 `db_compile_statement` 내부 구간 타이머 또는 perf로 분해해야 B의 기대 절감을 말할 수 있다.
2. **폴드에서 `prepare_query`/`execute_query`의 IPC가 실제로 제거됐는지**(`query_cl.c:74 qmgr_prepare_query` → `network_interface_cl.c`가 폴드에서 in-process 호출로 바뀌었는지)는 이번에 추적하지 않았다. §3.5의 "hop 제거"는 폴드 설계 전제에 근거한 서술이다.
3. **`PRM_FOR_QRY_STRING` 목록의 완전성.** 플랜에 구워지는데 플래그가 없는 파라미터가 있는지(예: collation 관련, `compat_mode`, `plus_as_concat` 등)는 검토하지 않았다. 결함 10이 보여준 클래스(`intl_date_lang`/`timezone`)는 목록에 있다.
4. **컬럼 메타의 세션 의존성.** `db_get_query_type_list` 결과(이름·타입·precision·charset)가 세션-유효 파라미터나 user에 따라 달라지는 사례가 있는지(B2의 전제) 미확인.
5. **SQL-level EXECUTE 경로의 chn 검사 등가성.** `PT_EXECUTE_PREPARE`가 `pt_has_modified_class`를 우회하고 서버측 xcache 검증만으로 충분한지(B5) — 코드에서 우회 사실은 확인했으나(`db_vdb.c:2224` 조건은 `xasl_id == NULL`일 때만 검사) 정확성 논증은 하지 않았다.
6. **`ux_end_tran`에서 핸들/결과의 정리 규칙**(holdable 커서 유지 조건)은 `hm_srv_handle_qresult_end_all` 호출처를 찾지 못해 인용하지 못했다.
7. **client-global-state.md / sa-mode-merge-boundary.md**는 git 히스토리로 존재를 확인했으나(커밋 `20d1c84`·`bfc594e`·`e674aee`) 본 조사에 직접 인용할 만한 핸들/xcache 관련 서술은 확인하지 않았다.
8. develop과 cas-merge의 `kept_trees`·bind-peek 코드가 동일한지(존재는 양쪽 확인: develop grep 11·7·10건) 세부 diff는 보지 않았다.

## 6. 인용 커밋·문서

- cas-merge: `7117c8a66`(tip), `9a563c11a`(REVOKE chn 범프), `7e59906e4`(drop 경로 revoke 순서), `f7fd0096d`(PR #192 A6 DDL-auth-server), `7b60bf436`(PR #237 wf171).
- develop 비교 기준 `6dbf6d92f`, merge-base `5ae45603f`.
- 워크스페이스 문서: `docs/research/cas-merge-final-gate-and-defect-log-1.md:301-305`(결함 10·11, PR cubrid#247), `docs/research/ycsb-baseline.md` @ `b7bf65b`(`:37-62`).
