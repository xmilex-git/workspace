# 공유 준비 객체 · 불변 native XASL · 실행별 상태 분리 — S0 설계 (workspace #266)

기준: `xmilex/cas-merge` **`c49af22e8`**(PR CUBRID/cubrid#7837 head, 2026-09-14 착수 시점 고정). 입력 결정은 [#216 resolution](https://github.com/xmilex-git/workspace/issues/216#issuecomment-5563976184)의 D1~D9와 [invalidation-policy.md](https://github.com/xmilex-git/workspace/blob/f3304fab3859d017a1e2e811b40bfb69bc2bf97c/docs/cas-merge/invalidation-policy.md). 사실 인용은 모두 `c49af22e8`의 `path:line`이다. 이 문서는 **설계이며 구현·측정 결과가 아니다**. 결정 요청(§10)은 사용자 확인 뒤 확정한다.

## 0. 요약

| 항목 | 내용 |
|---|---|
| 목표 구조 | ① 프로세스 스코프 **공유 준비 객체**(불변: SQL 원문·정규형·컬럼 메타·host-var 도메인·native XASL 정본) ② **세션 문장 핸들**(참조 + bind·커서·플래그·bind fingerprint) ③ **실행 인스턴스**(동시 실행 단위의 가변 상태) |
| 공유 범위 | 같은 DB 사용자(user OID) 안에서만. key = `(sha1(alias_print), prepare_flag 클래스, include_oid)`; alias_print에 `user=vol|page|slot`·`PRM_FOR_QRY_STRING` 파라미터·host-var 수가 이미 들어 있다(`parse_tree_cl.c:3071-3176`) |
| 현행 재사용 | xcache의 fix/unfix·related_objects 락·삭제 마크 재검사·RT 재컴파일·clone 풀(`xasl_cache.c:872-1210, 2330-2390`)과 SQL-level PREPARE 서술자(`session.c:100-109`, `db_vdb.c:3049-3103`)를 골격으로 승격 |
| 현행 사실 중 가장 중요한 것 | (a) 세션마다 파스→컴파일→alias_print→SHA1→컬럼 메타를 반복하고 xcache 히트는 XASL 생성만 건너뛴다(`cas_execute.c:830-953`). (b) xcache clone은 **이미 깊은 복사 캐시**라 clone 히트 경로에는 unpack이 없다 — P6의 이득은 clone 미스·PX 워커 재-unpack·clone 메모리에 한정된다(`xasl_cache.c:1095-1133`, `px_scan_task.cpp:570-611`). (c) SQL-level EXECUTE의 무-트리 fast path는 **SELECT 전용**이고 DML은 항상 재컴파일한다(`db_vdb.c:2144-2155`). (d) bind-sensitive 재계획은 **kept post-transform tree**에서 재생성한다(`db_vdb.c:2248-2280`) — P4(트리 미보유)와 직접 충돌 |
| 단계 | S1 native 정본+native clone → S2 실행 상태 분리(그룹별) → S3 공유 서술자 → S4 트리 해제·replan 입력 분리 → S5 무효화·회수 계약 → S6 회계·최종 게이트(#266 본문) |

## 1. 현행 사실 (c49af22e8)

### 1.1 prepare 경로 (세션 = 입양 커넥션 전용 스레드, 핸들 풀 = `CAS_TLS`)

| 단계 | 코드 | 세션마다 반복되는 것 |
|---|---|---|
| 핸들 할당 | `cas_handle.c:52-58` `srv_handle_table`은 `static CAS_TLS` → 핸들 ID는 세션 밖에서 무의미 | — |
| `ux_prepare` | `cas_execute.c:695-975`: `db_open_buffer`(830) → `db_include_oid`(845, updatable/OID) → `db_compile_statement`(853) → `prepare_column_list_info_set`(935) → `db_get_cacheinfo`(953) | 파스, 의미분석, alias_print, SHA1, XASL 생성(xcache 미스 시), 컬럼 메타 생성·net_buf 직렬화 |
| 컴파일 seam | `execute_statement.c:15287-15330`: `PT_NODE_PRINT_TO_ALIAS(... CUSTOM_PRINT_4_SHA_COMPUTE|PT_PRINT_DIFFERENT_SYSTEM_PARAMETERS|PT_PRINT_LOWER)` → `SHA1Compute` → `prepare_query` | xcache 히트면 XASL 생성·pack 생략(15312) |
| 핸들 소유물 | `cas_handle.h:119-165` `T_SRV_HANDLE`: `session`(DB_SESSION*: 파서+PT tree+`xasl_id`+host_variables+type_list), `q_result`(컬럼 메타·커서), `sql_stmt`, `classes/classes_chn`(할당만, 사용처 없음 — `cas_handle.c:171`만), `prepare_flag`·`is_prepared`·`is_updatable`·`is_pooled`·`auto_commit_mode`·`is_holdable`·`use_plan_cache` | 전부 세션 소유 |
| DB_SESSION | `db_session.h:26-50`: `parser`, `statements[]`, `type_list[]`, `include_oid`, `kept_trees`(SQL-level PREPARE용) | PT tree는 워크스페이스 MOP 내장(`parse_tree.h:2685`) → 직접 공유 불가(#212 C1) |

### 1.2 execute 경로

- `ux_execute` `cas_execute.c:1098-1330`: `hm_qresult_end` → (미준비/`CCI_EXEC_QUERY_INFO`면 재컴파일) → `make_bind_value`+`set_host_variables` → `db_set_statement_auto_commit`(1221; `statement->flag.use_auto_commit`을 **실행 시** 설정, `db_vdb.c:5071-5153`) → `db_execute_and_keep_statement`(1229) → `ER_QPROC_INVALID_XASLNODE`/`ER_HEAP_UNKNOWN_OBJECT` + `is_pooled` → `CAS_ER_STMT_POOLING`(1261-1263).
- `db_execute_and_keep_statement_local` `db_vdb.c:2007-2330`: (a) `xasl_id==NULL`이면 `pt_has_modified_class`(chn, MOP 의존; 2224) (b) **bind fingerprint**: `hv_pred_plan_unpeeked || db_is_bind_sensitive` && `xasl_id` → `histogram_bind_fingerprint` 비교 → 다르면 **kept post-transform tree에서 재계획**(2248-2280) (c) `do_execute_statement` (d) `ER_QPROC_INVALID_XASLNODE` 등 화이트리스트 에러면 `flag.recompile=1` → chn 재검사 → `do_prepare_statement`+재실행(2290-2320).
- `do_execute_select` `execute_statement.c`: 트리에서 쓰는 것 = `xasl_id`, `cache_time`, `flag.clt_cache_*`, `info.query.oids_included/into_list/do_cache`, `parser->host_variables`, `is_holdable`, `use_auto_commit`, `si_datetime/si_tran_id`, `query_trace`. → **전부 컴파일-시 상수 + 실행 플래그**: 서술자로 옮길 수 있다.
- `do_execute_update` `execute_statement.c:10203-10440`: `server_update`·`do_class_attrs`·`object`(UPDATE OBJECT)·`orderby_for` 자동 파라미터화(10324-10329)·`spec` 순회로 `sm_flush_objects`/`sm_flush_and_decache_objects`(10302-10306, 10389-10403, 10426-10439). `delete`/`insert`/`merge`도 동형(`server_delete`, `return_generated_keys`, `merge.flags`). → 서버측 DML(`server_update==1 && !do_class_attrs && object==NULL`)은 `xasl_id` + `spec의 flat class OID 목록` + 플래그만 있으면 실행 가능; 클라이언트측 DML(`do_class_attrs`, 트리거·메서드 개입)은 트리가 필요.
- 서버: `xqmgr_execute_query` `query_manager.c:1314` → `xcache_find_xasl_id_for_execute`(1379) → `qmgr_process_query(thread_p, xclone.xasl, ...)`(1548; **이미 in-memory XASL_NODE*를 받는 시그니처**, 1192) → `xcache_retire_clone`(1646).

### 1.3 xcache 엔트리·clone·무효화

- 엔트리(`xasl_cache.h:82-130`): `xasl_id`(sha1+time_stored+cache_flag=fix count/상태 비트), `stream`(packed), `sql_info`(hash text·user text·plan text), `related_objects[]`(클래스·serial OID+lock+tcard), `list_ht_no`, `mem_size`, **`cache_clones[]`+`cache_clones_mutex`**, `time_last_rt_check`. `ref_count`는 누적 사용 수이며 소유권은 `cache_flag`의 fix count다.
- 실행 시작 경계(`xasl_cache.c:969-1160`): sha1 조회 → RT 임계면 `ER_QPROC_XASLNODE_RECOMPILE_REQUESTED`(994-998) → `time_stored` 일치(1002) → related 클래스 전부 `lock_object`(1053-1075) → 삭제 마크 재확인(1079) → clone 풀 pop(1095-1125) → 풀이 비면 전역 heap으로 `stx_map_stream_to_xasl`(1128-1133).
- clone 반납(`2330-2390`): `n_cache_clones < max_plan_cache_clones(기본 1000) && entry_size < Max_plan_size`면 풀에 push — `assert(IS_XASL_INITIAL_STATUS(...))`(2327): **`qexec_clear_xasl`이 실행 후 초기 상태로 되돌린다는 계약**이 clone 재사용의 근거.
- 무효화 producer: `locator_sr.c:5674, 6297, 13952`(클래스 force/delete/update), `log_manager.c:5168`(트랜잭션 cleanup), `serial.c:1781`, `query_manager.c:2053`(sha1 지정), REVOKE는 `sm_touch_class` chn bump(폴드 전용, #135 D2). 통계 갱신은 RT check(`time_last_rt_check`, tcard) → recompile 요청 → 새 엔트리 게시·옛 엔트리 `TO_BE_RECOMPILED`→`WAS_RECOMPILED` 전이(1600-1730). **다른 실행은 옛 엔트리를 계속 쓴다**(fix 유지) — D6(통계 재최적화 중 기존 유효 계획 사용)은 현행 기계로 이미 충족되는 부분이 크다.
- 통계·메모리: `XCACHE_STAT_*`(lookups/hits/miss/inserts/recompiles/deletes/fix/unfix/cleanups)와 `xcache_dump`의 cache/clone 메모리(`2189-2221`). clone 수·clone 미스 카운터는 **없다** → P7에서 추가.

### 1.4 XASL의 가변 필드 (P6 write inventory 1차)

#214 §4.1의 목록을 `c49af22e8` 기준으로 재확인했다(`xasl.h` `struct xasl_node`, `query_executor.c` grep 계수).

| 그룹 | 필드 | 쓰기 지점 수(`query_executor.c`) | 분리 난이도 |
|---|---|---|---|
| G1 노드 실행 상태 | `status`(18), `query_in_progress`(8), `next_scan_on/next_scan_block_on`(10), `curr_spec`(22), `executed_parallelism`(4), `max_iterations` | 62 | 낮음 — 노드 id로 인덱스되는 per-execution 배열로 이동 가능 |
| G2 결과·통계 | `list_id`(126), `single_tuple`(15), `topn_items`(49), `orderby_stats/groupby_stats/xasl_stats/func_stats/analytic_stats`(46), `px_executor`(11), `memoize_storage`(44) | 291 | 중간 — 포인터 필드라 per-execution 슬롯으로 이동 가능하나 접근처가 많다 |
| G3 스캔 상태 | `ACCESS_SPEC_TYPE.s_id`(SCAN_ID 통째, 169), `parts/curent/pruned`(15), `s_dbval`(16), `grouped_scan/fixed_scan/cached_scan` | 200 | 중간 — `s_id`를 spec 외부 배열로 |
| G4 값 슬롯 | `instnum_val/save_instnum_val/ordbynum_val/level_val/isleaf_val/iscycle_val`(27+), `REGU_VARIABLE.value.dbval/dbvalptr`, `vfetch_to`, `arithptr->value`, `funcp->value`, `sp_ptr->value`, aggregate 누산기, `REGU_VARIABLE.domain`(실행 중 해석 후 복원), `flags`(FETCH_ALL_CONST 등) | 수천(`fetch.c` 5,347줄·`query_executor.c` 28,646줄 전반) | **높음** — 그래프 전체가 값 슬롯을 포인터로 참조; 인덱스 기반 값 아레나로 바꾸는 것은 실행기 전면 재작성 |

## 2. 소유권·수명 모델

```mermaid
flowchart LR
    subgraph P["프로세스 스코프 (불변, fix count 수명)"]
      D["shared_stmt 서술자<br/>key · SQL 원문/정규형 · stmt_type · 컬럼 메타(MOP-free) · host-var 도메인(packed) · 실행 플래그 상수 · tree_required"]
      G["세대 g_k: xcache 엔트리<br/>packed stream(외부/디스크 codec) · native XASL 정본 · related_objects"]
      D -->|현재 세대 1개 (D8)| G
    end
    subgraph S["세션 스코프 (mutable)"]
      H["T_SRV_HANDLE<br/>서술자 ref · 세대 ref(실행 중만) · bind 값 · q_result/커서 · autocommit/holdable/pooled · bind fingerprint · (tree_required일 때만) DB_SESSION"]
    end
    subgraph E["실행 스코프 (동시 실행 단위)"]
      X["exec 인스턴스<br/>G1~G3 상태 배열 · G4 값 슬롯(S2 범위까지) · list_id · query entry"]
    end
    H --> D
    H --> X
    X -->|fix| G
```

### 2.1 계층별 계약

| 계층 | 타입 | 소유자 | 생성 | 소멸 | 불변식 |
|---|---|---|---|---|---|
| 서술자 | `shared_stmt` (신규, 서버 측 `src/session/` 또는 `src/query/`) | 프로세스 캐시 `stmt_cache`(lock-free hash, xcache와 같은 lf 기반) | 첫 prepare 미스 시 그 세션의 워크스페이스·권한 아래에서 컴파일한 결과를 **값 복사**로 게시 | 참조 0 + (무효화 또는 용량 정리) | MOP·워크스페이스 포인터 없음(B1); key가 컴파일에 구워진 세션-유효 입력을 전부 담음(B2); 같은 user OID(B3) |
| 세대 | 기존 `XASL_CACHE_ENTRY` + `native_master`(신규 필드) | xcache | `xcache_insert` 시 첫 unpack 1회 | 마지막 unfix + 삭제 마크 | `native_master`는 게시 후 read-only; 실행은 정본을 직접 변경하지 않음 |
| 핸들 | `T_SRV_HANDLE` | 세션(CAS_TLS) | `ux_prepare` | `hm_srv_handle_free` / 세션 종료 | 서술자·세대에 대한 강한 pin은 **실행/커서 구간에서만**(D7); 유휴 핸들은 서술자 ref만 |
| 실행 인스턴스 | `xasl_exec` (S1: clone 그대로, S2: 상태 분리) | 실행 스레드(+PX 워커) | `xcache_find_xasl_id_for_execute` | `xcache_retire_clone`/query end | `qexec_clear_xasl` 초기 상태 복원 계약 유지 |

### 2.2 semantic key (D5, B2)

`key = { sha1(alias_print) , key_flags }` 로 xcache와 **같은 sha1**을 쓴다. alias_print에 이미 포함: 정규화 SQL(소문자·리터럴 정규화), `user=vol|page|slot`(`parse_tree_cl.c:3176`), `PRM_FOR_QRY_STRING` 플래그 파라미터(11종+, `system_parameter.c:1797-3924`; 결함 10/11 수정으로 세션 값 반영), host-var 수. **추가로 필요한 key_flags**(alias_print에 없고 컴파일 산출에 영향):

| 입력 | 근거 | 처리 |
|---|---|---|
| `include_oid`/updatable | `db_include_oid`가 컴파일 전 파서 플래그 설정(`cas_execute.c:845`, `db_vdb.c:1892`); 컬럼 리스트에 OID 포함 → xcache sha1이 같아도 컬럼 메타가 다름 | key_flags 비트 |
| `CCI_PREPARE_QUERY_INFO`/`CCI_EXEC_ONLY_QUERY_PLAN` | 플랜 덤프용 재컴파일(`cas_execute.c:1115-1125`, 최적화 레벨 514) | 공유하지 않음(세션-로컬 경로 유지) |
| `CCI_PREPARE_XASL_CACHE_PINNED` | `recompile_xasl_pinned` | 세대 교체 요청 신호로만; key 미포함 |
| `CCI_PREPARE_CALL` | SP 호출 `prepare_call_info` | 공유 제외(P 범위 밖) |
| autocommit/holdable | 실행 시 설정(`db_vdb.c:5104-5153`, `db_session_set_holdable`) | 핸들 필드(B7); key 미포함. 단 `use_auto_commit`이 XASL 생성에 영향을 주는지 S3에서 재확인(현재 근거상 실행 플래그) |
| 세션 `qo_optimization_level`·`qo_cost_overrides` | `client_session_context.hpp:145-155` — 옵티마이저 결과에 영향 | **alias_print에 없다면 key에 넣어야 한다** — S3 착수 시 확인 항목(현재 미확인) |
| 클라이언트 charset/collation·`compat_mode` | `PRM_FOR_QRY_STRING`에 포함 여부 확인 | 미확인 → S3 확인 |

### 2.3 서술자 내용 (P1/P2/P3)

`DB_PREPARE_INFO`(`db_query.h:149-166`) + SQL-level PREPARE 서술자(`session.c:100-109`)를 프로세스 스코프로 승격한 형태.

- SQL 원문(`sql_stmt`), alias_print(정규형), sha1, `stmt_type`, `num_markers`, `auto_param_count`.
- 컬럼 메타: `DB_QUERY_TYPE` 리스트(`db_query.h:126-139`)를 **packed 값**으로 보관(`db_pack_prepare_info`가 이미 값 직렬화). `SM_DOMAIN.class_mop`(`object_domain.h:81`)는 OBJECT 도메인일 때만 존재 → 서술자에는 `class OID + class name`으로 저장하고 세션이 필요 시 `tp_domains`(세션별, `client_session_context.hpp:130-142`)로 복원. YCSB/일반 OLTP 컬럼은 non-OBJECT라 복원 비용 없음.
- host-var expected domains: 동일 규칙(packed, OBJECT 도메인은 OID 참조).
- 실행 상수: `oids_included`, `do_cache`, `into_list`, `clt_cache_check` 가능 여부, `si_datetime/si_tran_id`, `is_bind_sensitive`/`hv_pred_plan_unpeeked`, DML의 `server_update/server_delete`·`do_class_attrs`·`return_generated_keys` 허용 여부·`spec` 클래스 OID 목록(flush 대상), `subquery_info`.
- `tree_required`(§4) 판정 결과.
- `cacheinfo`(`use_plan_cache/use_query_cache`).
- 무효화 근거: 세대 ref(xcache sha1) + `related class OID·chn 스냅샷`(B5 대체: 실행 시작 경계의 related_objects 락·재검사가 서버측에서 이미 보장하므로 chn 스냅샷은 **핸들 재준비 판단용**).

세션 핸들 재사용 세션이 건너뛰는 것: 파싱·의미분석·alias_print·SHA1·컬럼 메타 생성·net_buf 컬럼 정보 재계산(캐시된 바이트열 재전송 가능). 원문→서술자 조회는 **원문 문자열 1차 키**(`(user OID, 원문, key_flags)` → 서술자)로 파싱 없이 도달한다(#212 B 비용 프로필의 전단 캐시). 1차 키 히트 후에도 권한 freshness는 §3의 세대 검증으로 보장한다.

## 3. 세대·무효화·회수 계약 (D6/D7, invalidation-policy 축자)

| 변경 | 서술자 | 세대(xcache) | 핸들 | 실행 중 인스턴스 |
|---|---|---|---|---|
| 스키마 DDL(force/delete/cleanup) | related 클래스 OID로 서술자 **hard-invalid** 마크(`xcache_remove_by_oid`와 같은 producer에 연결) | 기존 삭제 마크·마지막 unfix 회수 | 다음 execute에서 서술자 세대 불일치 → 자기 워크스페이스로 재컴파일·새 서술자 게시(`CAS_ER_STMT_POOLING` 외부 계약은 pooled 핸들에서만, 비-pooled는 내부 재준비) | 보호(fix) — 기존 `lock_object`+삭제 마크 재검사 경계 유지 |
| REVOKE/owner/group | `sm_touch_class` chn bump → 같은 경로 | 동일 | 재컴파일이 권한 재검사(`au_fetch_class`) | 강제 취소 없음 |
| 통계만 변경 | 서술자 유효 유지 | RT check → 첫 요청이 재컴파일·새 엔트리 게시, 다른 실행은 옛 세대 계속 사용(현행) | 세대 ref만 갱신 | 옛 세대는 마지막 unfix 후 회수 |
| 세션 설정 변경(`PRM_FOR_QRY_STRING`·opt level) | 다른 key로 resolve | — | 핸들이 새 서술자로 재바인딩 | — |
| 미커밋 DDL 참조 컴파일 | **게시 금지**: 컴파일 세션의 트랜잭션이 대상 클래스에 SCH_M/변경을 보유하면 서술자를 transaction-private로 두고 commit 후 committed 기준으로 재컴파일·게시 | xcache는 현행대로(엔트리 삽입은 커밋 무관 — 현행 동작 보존, 새 계약은 서술자 계층에만) | — | — |
| 용량 부족 | 유휴(참조 실행 0) 서술자의 **큰 부분**(컬럼 메타 packed·native 정본)만 회수, 소형 identity(원문·sha1·key)는 유지 → 다음 사용 시 재준비 | clone 풀 정리(현행 cleanup) + native 정본 회수 | 핸들은 유지(D7) | 보호 |

- 회수 예산: `stmt_cache` 바이트 예산은 `max_plan_cache_entries`와 별개의 파라미터(§10 D-EVICT). pinned bytes(실행/커서 참조)와 reclaimable bytes를 분리 계상; hard cap이 아니다.
- 재시도 경계: 실행 전 stale 판정(세대 불일치·`ER_QPROC_INVALID_XASLNODE` 화이트리스트)만 내부 재준비; 부작용 시작 후 런타임 에러는 재시도하지 않는다(현행 `db_vdb.c:2290-2320` 화이트리스트 유지).
- compile·publish 경합: 같은 key의 동시 미스는 첫 컴파일이 게시하고 나머지는 `found_at_insert`처럼 게시본을 채택(중복 컴파일 상한 = 동시 미스 수; 대기 합치기는 S3 측정 후 결정).

## 4. P4 — 트리 미보유 실행과 `tree_required`

서술자 히트 세션은 DB_SESSION/PT tree를 만들지 않고 실행해야 P4가 성립한다. 현행 무-트리 실행 선례는 SQL-level EXECUTE의 SELECT 경로뿐이다(`db_vdb.c:2144-2155`; DML은 `do_recompile=true`). 따라서 **XASL-only 실행 경로**를 statement class별로 신설한다.

| 문장 클래스 | 무-트리 실행 조건 | 필요한 서술자 상수 |
|---|---|---|
| SELECT (holdable 포함) | 항상 | `xasl_id`, 컬럼 메타, `oids_included`, `do_cache`, cache_time 규칙, `into_list`(csql만) |
| UPDATE/DELETE (server-side) | `server_update/server_delete==1 && !do_class_attrs && object==NULL && 트리거·메서드 없음` | `xasl_id`, flush 대상 클래스 OID, `orderby_for` auto-param 여부, `waitsecs_hint` |
| INSERT (server-side XASL) | `xasl_id != NULL && !return_generated_keys-트리 의존 경로` | `xasl_id`, generated keys 처리용 클래스 OID |
| MERGE | server-side 조건 동형 | 동형 |
| 그 외(DDL·SP CALL·클라이언트측 DML·트리거 개입·`CCI_EXEC_QUERY_INFO`) | **`tree_required=1`** — 현행대로 세션이 DB_SESSION을 보유·실행(공유 서술자는 identity·컬럼 메타만) | — |

`tree_required`는 컴파일 시 판정해 서술자에 기록한다. 판정 술어의 완전성은 S4 게이트(CTP sql·medium 전량 + 트리거/메서드/뷰 TC)로 검증하며, 판정 누락은 **트리 보유 쪽으로 보수적으로** 떨어지게 기본값을 둔다.

## 5. P5 — bind-sensitive 재계획 입력의 분리

현행: fingerprint(`histogram_bind_fingerprint`)가 달라지면 kept post-transform tree에서 재계획(`db_vdb.c:2248-2280`). 트리 없이 재계획하려면 두 선택지:

- **(a) 원문 재컴파일**: 세션이 일시 파서로 원문을 다시 컴파일(파스+의미분석 반복; fingerprint가 바뀔 때만 발생) → 새 세대 게시. 트리 0 보유. 비용은 replan 빈도에 비례(P7 카운터 `replan_count`로 실측).
- **(b) bind-sensitive 문장만 kept tree 세션-로컬 보유**: `is_bind_sensitive || hv_pred_plan_unpeeked`인 서술자에 한해 핸들이 트리를 유지. 나머지 문장은 트리 0.

권고 = **(a) 기본 + (b)를 파라미터로 남기지 않음**(단순성; #216 D8 단일 현재 계획과 정합: 세대 교체는 서술자의 현재 세대 갱신으로 표현). fingerprint 자체는 핸들 필드(mutable, 공유 안 함). → §10 D-P5.

## 6. P6 — 불변 native 정본과 실행 인스턴스

### 6.1 이득의 실제 위치(실측 전 근거)

- clone 풀 히트 = unpack 0회(§1.3). 미스 = 스레드 수 > 풀 크기, 첫 실행, 풀 정리 후, `max_plan_cache_clones=0`, 그리고 **PX 워커**(`px_scan_task.cpp:595-598` 비-clone 경로는 매번 재-unpack).
- 메모리: 엔트리당 clone ≤ 1000 × (stream×3 아레나 + DB_VALUE payload). L7 sweep(연결 100 × 문장 64)에서 clone 바이트를 실측(P7 `clone_bytes`).
- 따라서 P6의 속도 이득은 **clone 미스율×unpack 비용**이고, 메모리 이득은 **clone 수×clone 크기**다. S0 기준선에서 두 수치를 먼저 측정한다(§8).

### 6.2 선택지

| 안 | 내용 | 비용 | 이득 |
|---|---|---|---|
| A. 전면 분리 | G1~G4 전부 per-execution 아레나(인덱스 참조)로, 정본은 다중 스레드가 직접 실행 | 실행기·fetch 전면 재작성(43k줄 영향) | clone 0, unpack 1회/세대, PX 워커 복사 0 |
| B. native 정본 + native 복사기 | 정본 1벌 unpack; clone/PX 인스턴스는 stream 대신 **native 그래프 복사기**(`stream_to_xasl.c` 6,953줄의 방문자 구조를 복사기로 재사용)로 생성 | 복사기 신설(방문자 재사용), 실행기 무변경 | unpack→memcpy형 복사(속도), 메모리 동일 |
| **C. 단계적(권고)** | S1 = B; S2 = G1→G2→G3 순으로 상태를 exec 인스턴스로 이동해 복사 대상을 줄이고, G4는 값 아레나로 **복사 유지** | S1 소·중, S2 그룹별 게이트 | 매 그룹마다 clone 크기·복사 비용 감소를 실측; A로 가는 경로를 닫지 않음 |

C에서 "불변 정본 1벌"은 S1에서 달성되고, "실행별 상태 분리"는 S2에서 G1~G3까지 달성된다. G4(값 슬롯)는 per-execution **값 아레나 복사**로 남는다 — 이는 D4의 "실행별 mutable 상태" 요건을 충족하되(정본 무변경), 그래프 전체 재작성은 실측 이득이 입증될 때만 연다(§10 D-P6).

### 6.3 S1 seam

- `XASL_CACHE_ENTRY`에 `native_master`(unpack 1벌, 전역 heap, `xasl_unpack_info` 보유) 추가; `xcache_insert` 뒤 첫 실행이 lazily 생성(엔트리 뮤텍스 아래 1회).
- `xcache_find_xasl_id_for_execute` 1128-1133: 풀 미스 시 `stx_map_stream_to_xasl` → `xasl_native_copy(native_master)`.
- `px_scan_task.cpp:595-598`: 비-clone 경로도 정본 복사로.
- packed stream은 유지(외부 codec: `sqmgr_*`·유틸·인덱스 술어 디스크 영속·`prepare_query` 게시). 내부 왕복 제거는 "실행 인스턴스 생성 시 stream을 읽지 않음"으로 정의.
- 규칙: GLOB-03(정본은 불변일 때만 공유), MEM-02/05(정본 hot/cold 분리는 S2), ALLOC-07/08(인스턴스 할당은 실행 스레드 소유·같은 스레드 해제), COH-04(엔트리 fix 라인 HITM — `cache_clones_mutex`·`native_master` 초기화 뮤텍스를 별 캐시라인에), MEAS-04/06(median-of-3, 1차 지표 우선).

## 7. 외부 JDBC 호환 (wire 무변경)

- `serverHandler` identity·lifetime, CLOSE/deferred close, marker·컬럼 메타, prepare flags, autocommit/generated keys, per-execution bind/result/cursor 유지.
- pooled 핸들 무효화: `ER_QPROC_INVALID_XASLNODE`/`ER_HEAP_UNKNOWN_OBJECT` → `CAS_ER_STMT_POOLING` → 드라이버 1회 재prepare(`UStatement.java:950-1014`) — 현행 계약 유지. 비-pooled 핸들은 서버 내부 재준비(현행 `db_vdb.c:2290-2320` 동형).
- 세대 회수(D7)로 핸들이 가리키는 세대가 사라진 경우: execute 전에 서술자 현재 세대로 재바인딩(내부), 서술자 자체가 hard-invalid면 위 경로.
- 검증: pinned/non-pinned × pooling on/off에서 동작 동일; 100 연결 동일 SQL → 서술자 1·핸들 100·실행 인스턴스 ≤ 동시 실행 수(P7 카운터로 계수).

## 8. P7 회계 (S0에서 기준선 채집, S6에서 노출)

| 카운터 | 위치 | 용도 |
|---|---|---|
| `stmt_cache.{entries, hits, misses, publishes, private_compiles, evictions, bytes_pinned, bytes_reclaimable}` | 신규 | 서술자 효과 |
| `xcache.{clone_hits, clone_misses, clone_count, clone_bytes, master_bytes, px_copies}` | `xasl_cache.c` XCACHE_STAT_* 확장 + `xcache_dump` | P6 이득 위치 실측 |
| `session.{handles_live, handles_with_tree, exec_instances_live, replan_count}` | 세션 통계(SHOW 계열, #265 축 6과 조정) | P4/P5 효과 |

노출: `cubrid statdump`(perfmon watcher 필요 — SSOT 주의)와 `SHOW` 스냅샷. 기준선(S0)은 `xcache_dump`·`XCACHE_STAT`·smaps로 대체 측정한다.

## 9. 단계·게이트 (#266 본문과 동일, 검증 항목 구체화)

| 단계 | 브랜치 | 구현 | 게이트 |
|---|---|---|---|
| S1 | `feat/shared-prepare/S1` | `native_master` + `xasl_native_copy` + PX 워커 경로 | 양 모드 incremental build·unit(server_compile)·smoke 14·`just ctp sql` 샤드·churn C×1·clone 카운터 |
| S2 | `.../S2` | G1 → G2 → G3 상태 이동(각각 커밋 단위), `qexec_clear_xasl` 계약 갱신 | 각 그룹: CTP sql·medium 전량, optdebug assert, YCSB C×1/A×1 비악화 |
| S3 | `.../S3` | `stmt_cache` 서술자·원문 1차 키·핸들 재바인딩·컬럼 정보 바이트열 캐시 | CTP sql·medium, JDBC smoke(pinned/pooling 4조합), churn C×3, L7 sweep |
| S4 | `.../S4` | XASL-only 실행 경로(SELECT/서버측 DML), `tree_required`, P5 (a) | CTP sql·medium 전량 + 트리거/메서드/뷰/PREPARE-EXECUTE/query-info 계열, PSS 100/1,000 |
| S5 | `.../S5` | 서술자 hard-invalid producer 연결, private 게시 금지, 예산·회수, `CAS_ER_STMT_POOLING` 호환 | invalidation-policy 검증 7항 재현 스크립트(리드가 QA test.md 요구사항으로 기록) + unit, CTP shell 관련 계열 |
| S6 | `.../S6` | P7 노출, 최종 측정·문서 | YCSB C×3·A×3·churn ×3·L7·PSS vs S0, cas-merge 합류 |

## 10. 결정 요청 (HITL — 사용자 확인 후 확정)

| ID | 질문 | 권고 |
|---|---|---|
| D-P6 | §6.2의 A/B/C 중 무엇으로 가는가. C면 G4(값 슬롯)를 per-execution 복사로 두는 것을 "실행별 상태 분리" 달성으로 인정하는가(정본은 무변경) | **C**; G4 전면 분리는 S2 실측(clone 바이트·미스율)이 정당화할 때 별도 단계로 |
| D-P5 | bind-sensitive 재계획 = (a) 원문 재컴파일 / (b) bind-sensitive 문장만 kept tree 보유 | **(a)** — 트리 0, D8 정합 |
| D-P4 | `tree_required` 문장(DDL·SP·클라이언트측 DML·트리거 개입)은 현행 세션 트리 보유로 남기는 것을 허용하는가 | **허용**(보수적 기본값; 서술자는 identity·메타만 공유) |
| D-KEY | key_flags에 `include_oid`/updatable을 넣고, `qo_optimization_level`·`qo_cost_overrides`·charset 항목은 S3 확인 결과에 따라 key 편입 | 권고대로 |
| D-EVICT | 서술자 캐시 예산 파라미터 신설(`max_prepared_stmt_cache_size` 류, 기본값은 S6 실측 뒤) vs xcache 예산 공유 | **신설**, 기본값은 S6에서 |
| D-PRIVATE | 미커밋 DDL 참조 컴파일의 "게시 금지"를 서술자 계층에만 적용(xcache 현행 유지) | 권고대로(범위 최소) |
| D-PX | PX 워커의 인스턴스 생성을 S1에서 함께 native 복사로 바꾸는가 | **예**(같은 seam) |

## 11. QA `test.md` 요구사항 (초안; S5/S6에서 완성)

invalidation-policy §검증 계획 1~7항을 그대로 요구사항으로 옮기고, 추가로: (8) 100 연결 동일 SQL의 서술자/핸들/인스턴스 계수, (9) pinned/pooling 4조합의 `CAS_ER_STMT_POOLING` 동작 동일성, (10) `tree_required` 문장(트리거·메서드·뷰 갱신·DDL)의 결과 동일성, (11) 예산 초과 시 유휴 회수 후 재실행 정확성, (12) PX 병렬 질의(`parallelism>1`)의 결과 동일성. 신규 TC는 QA가 작성하며 이 노력은 PR에 TC를 추가하지 않는다.
