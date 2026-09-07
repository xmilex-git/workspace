# 준비 객체·컴파일·XASL 공유 감사

이 문서는 정적 조사 당시의 사실·대안을 보존한다. 현재 결정은 [최종 판정](../candidate-disposition.md)과 [브레인스토밍](../optimization-brainstorm.md)을 따른다.

- 대상: `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/wf216/engine` HEAD `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`
- 비교 기준: upstream `e374c7a24c46449c3f79e9413a6f4ff3d23b16c2` (merge-base와 동일)
- 범위: CAS statement handle, DB_SESSION/parser/optimizer retained tree, query metadata/domain, SQL PREPARE, XASL/xcache. workspace/schema와 PL/transport는 다른 감사 범위다.
- 방법: 현재 소스의 생성·보유·해제 경로를 읽었다. 빌드·실행·측정은 하지 않았다. 따라서 성능 수치는 주장하지 않고, 메모리 차수와 측정 지점을 제시한다(MEAS-01/04/06/07).

## 1. 현재 소유권 지도

| 계층 | retained 상태 | 생성/보유/해제 | 공유성 |
|---|---|---|---|
| CAS handle | `T_SRV_HANDLE` 안의 SQL 복사본, `DB_SESSION*`, `T_QUERY_RESULT*`, prepare/execute/cursor/transaction 플래그 | `hm_new_srv_handle`: `cas_handle.c:61-137`; SQL 복사 `cas_execute.c:707-724`; session+result 결합 `:911-940`; `srv_handle_content_free`→`hm_qresult_end`/`hm_session_free`: `cas_handle.c:303-369,379-410` | `srv_handle_table`과 카운터가 `CAS_TLS`: `cas_handle.c:52-58`. 세션별/스레드별 |
| compiled client-half | `DB_SESSION`: parser, PT tree 배열, type list, SQL-level PREPARE용 kept subsession | `db_session.h:26-49`; parse/compile `db_vdb.c:468-512,826-1120`; close가 type list, xasl_id, PT tree, host values/domain vector, parser를 해제 `:4272-4344` | handle/session 소유. PT tree의 MOP와 parser mutable 값 때문에 직접 공유 불가 |
| CAS metadata | `T_QUERY_RESULT.column_info`(`DB_QUERY_TYPE`), update-column 문자열, null bitmap, 실행 결과/커서 | 구조 `cas_handle.h:73-88`; 생성/네트워크 인쇄 `cas_execute.c:6867-7050`; free `cas_handle.c:310-359,447-461` | 현재 세션 handle 소유. immutable metadata와 mutable cursor가 한 객체에 혼재 |
| server SQL PREPARE descriptor | `{name, alias_print, sha1, info_length, packed info}` | `session.c:100-109`; 인자를 복사하지 않고 소유권 인수 `:1763-1799`; lookup마다 info 복사 `:1891-1959`; free `:552-584` | server session별 linked list. XASL lookup만 process-shared xcache 사용 |
| XASL cache | packed `XASL_STREAM`, SQL hash/user/plan text, related objects, header flag, mutable clone pool | `xasl_cache.h:71-130`; insert/문자열 연속 복사 `xasl_cache.c:1465-1600`; uninit `:551-617`; execute clone pop/unpack `:969-1138`; retire `:2316-2388` | 프로세스 공유. stream 1개 + 동시/유휴 clone 여러 개 |
| execution | `QMGR_QUERY_ENTRY`, bind copy, list/result state, 한 XASL clone의 scan/aggregate/runtime state | `query_manager.c:1368-1555,1639-1649`; XASL clear/reset `query_executor.c:1395-1650,1850-1970,2333-2435` | 트랜잭션/실행별. 공유하면 안 되는 상태 |

메모리 차수의 확실한 결론은 수치가 아니라 중복 축이다. 같은 SQL을 S개 세션이 각각 K개 handle로 유지하면 CAS SQL 문자열, DB_SESSION/parser/PT tree, type list가 `O(S×K)`로 유지된다. xcache의 stream/SQL text는 동일 cache key당 `O(1)`이지만 clone 메모리는 해당 plan의 관측된 동시 실행 수와 cache 정책에 따라 늘어난다. 정확한 bytes는 allocator 계측 없이는 알 수 없다.

## 2. 공유 후보

### P1. `T_SRV_HANDLE`을 immutable prepared descriptor와 mutable execution handle로 분리

- **현재 증거**: `T_SRV_HANDLE`은 `session`, SQL, q_result, cursor 위치, autocommit/holdable, query-info/recompile 및 replacement 상태를 한 구조에 둔다(`cas_handle.h:117-169`). prepare는 SQL 복사와 DB_SESSION 전체를 handle에 보유한다(`cas_execute.c:707-724,817-940`). execute는 bind를 parser에 넣고, result/cursor와 플래그를 갱신한다(`:1085-1217,1276-1317`).
- **CAS 시대 이유/잔류**: handle ID가 CAS 프로세스 주소공간의 state를 가리키는 구조였다. 폴드 후 표만 `CAS_TLS`가 되었고, 소유 모델은 그대로다(`cas_handle.c:52-58`).
- **경계**: 공유 descriptor에는 cache key, canonical SQL 참조, stmt type, marker count, prepare-shape flags, immutable result metadata와 plan lookup handle만 둔다. 세션 handle에는 bind values, cursor/result, autocommit/holdable, query-info, replacement fallback, per-transaction 상태와 descriptor ref만 둔다.
- **위험**: key가 user/권한과 모든 plan/metadata 영향 세션 파라미터, `include_oid`/updatable, query replacement identity를 포함해야 한다. REVOKE/DDL/statistics invalidation과 descriptor 수명이 xcache보다 길거나 짧을 때의 계약이 필요하다. C 코드 hot path에 원자 refcount를 매 실행 복사하면 CPP-01/PAR-10 위험; epoch/entry fix 또는 세션별 ref의 장기 보유를 검토해야 한다. cross-thread free는 global heap이어야 한다(ALLOC-08).
- **메모리/YCSB**: 목표와 직접 일치한다. 동일 SQL을 여러 세션이 prepare하면 descriptor 부분을 `O(S×K)`에서 key당 `O(1)`로 바꿀 수 있다. 단 DB_SESSION/PT tree까지 descriptor에 넣으면 P4의 안전 문제가 재발한다. YCSB가 여러 연결에서 같은 prepared SQL을 장기 보유할 때 노출되지만, 실제 driver statement-pool handle 수와 재prepare 빈도를 먼저 계측해야 한다.
- **규칙**: MEM-05(immutable/cold와 mutable/hot 분리), COH-04(공유 read-only와 write 분리), COH-12(공유 대신 소유권 분할), ALLOC-08, MEAS-01.

### P2. SQL 문자열과 key material을 process-level로 intern/deduplicate

- **현재 증거**: CAS는 입력 SQL을 handle마다 `ALLOC_COPY_STRLEN`한다(`cas_execute.c:717`). PT statement/parser도 `sql_user_text`와 `alias_print`를 보유하며, xcache는 `sql_hash_text`, `sql_user_text`, `sql_plan_text`를 하나의 새 buffer로 복사한다(`xasl_cache.h:71-80`, `xasl_cache.c:1518-1544,1587-1589`). SQL-level PREPARE는 별도로 `alias_print`와 packed info 속 statement를 세션에 보유한다(`session.c:100-109`; `db_vdb.c:2954-3000`).
- **경계**: P1 descriptor가 canonical SQL/hash text를 소유하고 handle/parser는 view 또는 descriptor ref를 사용한다. xcache logging text와 descriptor text의 공동 string pool은 가능하지만 xcache eviction 뒤에도 descriptor가 살아야 하므로 독립 lifetime/ref가 필요하다.
- **위험**: 원문은 로깅·오류 위치·query replacement/self-heal에 필요하고 normalization text와 같지 않다. charset/collation 및 길이 기준 비교가 필요(STR-02/04). SHA1 하나만으로 identity를 확정하지 말고 충돌 시 bytes를 비교해야 한다. 문자열 view가 parser arena/handle보다 오래 살면 UAF.
- **메모리/YCSB**: 중복은 SQL 길이에 비례해 `O(S×K×|SQL|)`. YCSB SQL은 짧고 종류가 적을 가능성이 있어 총 RSS 효과는 parser/PT tree보다 작을 수 있으므로 별도 계측한다. 준비 횟수가 아니라 retained handle snapshot으로 검증한다.
- **규칙**: STR-01/03/04, DS-03(SHA를 hot-path 선택으로 새로 도입하지 않음), MEM-05.

### P3. 결과 metadata를 immutable compact descriptor로 공유

- **현재 증거**: prepare마다 `db_get_query_type_list`를 얻고 linked `DB_QUERY_TYPE`를 걸어 CAS wire metadata를 만든다(`cas_execute.c:6867-7032`). `DB_QUERY_TYPE`의 생성/복사는 노드별 malloc과 문자열/domain 복사를 한다(`db_query.c:910-967,1372-1518`); free는 list 순회(`:168-190,1855-1878`). 그러나 CAS `T_QUERY_RESULT`은 이 metadata와 mutable `result`, tuple_count, holdable/cursor 상태를 한 구조에 둔다(`cas_handle.h:73-88`).
- **경계**: wire에 필요한 고정 metadata를 contiguous offset-based blob으로 descriptor에 한 번 저장하고, execute/fetch state는 별도 객체로 둔다. SQL-level PREPARE의 `DB_PREPARE_INFO` pack/unpack(`db_query.c:208-370,680-735`; `db_vdb.c:2992,3067-3127`)가 pointer-free 값 표현의 선례지만, 현재는 session마다 보유/lookup마다 복사한다.
- **위험**: updatable column metadata(`attr_name`, `class_name`, include_oid), client protocol/version과 `max_string_length`, charset/domain 표시, 다중 statement가 shape를 바꾼다. `TP_DOMAIN*` 자체는 공유 대상이 아니며 직렬 값 또는 재구성 계약이 필요하다. 외부 포맷이라면 framing 검증(SER-02), 내부 blob은 offset 기반(SER-01/03).
- **메모리/YCSB**: SELECT column 수와 문자열 길이에 따라 handle당 linked-node 비용이 `O(S×K×columns)`이다. 단 `prepare_column_list_info_set`는 로컬 `column_info`를 wire 작성 뒤 해제하는 경로도 있어(`cas_execute.c:7030-7032`), 실제 retained `q_result->column_info`는 schema/out-RS 등 경로와 구분해 heap snapshot으로 확인해야 한다. 단순 YCSB PK SELECT는 컬럼 수가 적어 효과를 과대평가하면 안 된다.
- **규칙**: DS-01, STR-03, SER-01/02/03, MEM-01/05.

### P4. parser/PT tree를 직접 공유하지 말고, immutable compiler artifact를 새로 정의

- **현재 증거**: `DB_SESSION`은 parser, statement PT tree, type list를 handle 수명 동안 유지한다(`db_session.h:26-49`; close `db_vdb.c:4272-4344`). execute는 parser의 host variables/expected domains를 교체하고 PT statement의 bind fingerprint, flags, XASL_ID를 갱신한다(`db_vdb.c:2224-2309`; `cas_execute.c:1132-1217`). PT name nodes는 workspace MOP/chn을 포함하는 기존 조사와 일치한다.
- **경계**: 공유하려면 현 PT_NODE를 const로 선언하는 수준이 아니라 (a) workspace pointer 없는 resolved IDs/schema epochs, (b) optimizer input의 immutable logical plan, (c) 실행/바인드별 overlay를 별도 표현으로 만들어야 한다. 우선 P1 descriptor가 xcache XASL을 참조하고 parser는 miss/replan에만 생성하는 방식이 더 작은 단계다.
- **위험**: compile-time auth, uncommitted DDL visibility, session parameters, MOP/TP_DOMAIN lifetime, LIKE/MRO/bind-sensitive replan, query-info plan dump. parser 함수들이 in-place transform을 넓게 수행하므로 shallow copy나 mutex 직렬화는 안전한 공유가 아니다. mutex는 메모리 절감 대신 prepare tail과 contention을 만들 수 있다(PAR-10).
- **메모리/YCSB**: 현재 가장 큰 `O(S×K)` 후보일 수 있으나 bytes 측정이 없다. YCSB warm execution은 retained memory를 보여도 compile CPU를 거의 보여주지 않는다. connection/statement count를 sweep하면서 parser heap/PT node counts와 RSS를 함께 재야 한다.
- **규칙**: COH-04/12, MEM-05, PAR-10, correctness 우선 규약.

### P5. bind-sensitive `kept_trees`의 session duplication을 descriptor 설계에 포함

- **현재 증거**: SQL-level PREPARE는 post-transform tree subsession을 owner session의 `kept_trees`에 이름별 보관해 histogram bucket 변화 때 parse/semantic 없이 replan한다(`db_vdb.c:193-207,217-365`; `db_session.h:40-48`). first/later bind fingerprint는 statement/parser mutable state다(`db_vdb.c:2240-2283`). owner close가 kept tree를 재귀 해제한다(`:4282-4293`).
- **경계**: P1/P4가 일반 prepared object를 만들 때 kept tree를 누락하면 bind-sensitive SQL만 다시 `O(S×K)` tree를 유지하거나 매번 full compile한다. 선택지는 (a) immutable logical-plan snapshot+세션 bind fingerprint overlay, (b) tree 없이 SQL에서 재compile, (c) 현행 세션 tree 유지다.
- **위험**: histogram/statistics invalidation, user/session key, mutable flags와 MOP. YCSB 데이터/통계에서 bind fingerprint가 실제로 달라지는지 측정 없이 (a)의 우선순위를 높일 수 없다.
- **메모리/YCSB**: SQL-level PREPARE 경로의 명시적 retained duplication이다. JDBC/CCI prepared statement는 같은 `PT_NODE`에 fingerprint를 보유하므로 P4와 함께 다뤄야 한다. YCSB bind 분포와 `plan_cache_bind_sensitivity` 설정을 기록해야 한다.
- **규칙**: MEAS-01/06, MEM-05, COH-12.

### P6. xcache를 `immutable native plan` + `per-execution state`로 재설계하고 내부 stream canonicality 제거

- **현재 증거**: cache entry는 packed stream과 clone pool을 같이 보유한다(`xasl_cache.h:88-125`). execute는 clone을 pop하고, 없으면 stream을 전역 heap arena로 unpack한다(`xasl_cache.c:969-1138`); 종료 시 `qexec_clear_xasl`로 초기 상태를 복구해 pool에 되돌리거나 free한다(`:2302-2388`). `qmgr_process_query`는 이미 `XASL_NODE*` 직접 입력 seam을 갖는다(`query_manager.c:1167-1242`).
- **mutable 필드**: `XASL_NODE`의 `list_id`, `curr_spec`, stats/topn, status, query_in_progress, next_scan flags, px_executor, memoize storage (`xasl.h:1120-1245`); `ACCESS_SPEC_TYPE`의 `s_dbval`, `SCAN_ID`, partitions/current/pruned (`:1070-1110`); REGU variable의 domain/original_domain, vfetch target, DB_VALUE, aggregate/function/SP scratch (`regu_var.hpp:125-205`). clear는 scan stats/partition arrays/DB_VALUE/caches/parallel managers를 실제 free/reset한다(`query_executor.c:1395-1650,1850-1970,2333-2435`). 즉 현 XASL은 immutable plan이 아니다.
- **구조적 목표**: cache에는 MOP-free immutable native graph를 한 번 보유하고, 실행마다 compact `XASL_EXEC_STATE` arena/arrays를 만든다. immutable node는 state slot index를 가지며 scan/list/aggregate/function/memoize/px 상태는 slot으로 이동한다. executor API가 `(const plan, exec_state)`를 받도록 단계적으로 바꾼다. 병렬 worker도 stream 재-unpack 대신 같은 immutable plan+자기 state를 사용한다.
- **stream 경계**: CS_MODE wire와 카탈로그에 영속되는 filter/function predicate는 stream을 유지한다. 같은 프로세스 compile→cache는 native plan builder/freeze를 사용하고, 필요할 때만 외부/persistent codec을 호출한다. cache 존재와 cache representation은 독립 결정이다.
- **pack/unpack이 현재 제공하는 숨은 기능**: 포인터 graph deep-copy/relocation, MOP→OID 정규화, parser arena에서 global lifetime arena로 이전, clone별 independent mutable graph, `packed_xasl`을 통한 PX worker 복제. 대체 설계는 이 네 계약을 명시적으로 제공해야 한다. `xasl_stream.cpp:74-107`의 unpack arena와 `stream_to_xasl.c:212-269`, PX `px_scan_task.cpp:570-611`가 검증 지점이다.
- **단계안**: P6a mutable-field inventory+write instrumentation; P6b 한 leaf plan/access-spec에서 state slot 분리; P6c native freeze/ownership arena와 OID normalization visitor; P6d serial executor 전환; P6e parallel/APTR·memoize·SP/JSON 등 확장; P6f in-process cache insertion을 native로 전환하되 external codec round-trip tests 유지; P6g clone pool/stream canonical representation을 내부 경로에서 제거.
- **위험/규모**: executor 전반의 큰 리팩터링이다. 누락된 write는 cross-execution race/오답이 된다. 현재 `qexec_clear_xasl`의 복잡성이 곧 inventory가 전수 아님을 보여준다. shared immutable memory와 per-worker state를 분리하면 COH-04/12에 맞지만 state slot 간 false sharing(MEM-03), arena cross-thread free(ALLOC-08), parallel-only path 누락(PAR-14), serialization compatibility(SER-02/03)를 검증해야 한다.
- **메모리/YCSB**: 현재 key당 stream 1개와 cached clone N개가 모두 full graph를 보유한다. 재설계는 immutable graph를 key당 1개, mutable state를 동시 실행 수만큼 보유하는 방향이다. 절감량은 `stream bytes + clone arena bytes`와 분리 후 plan/state bytes를 측정해야 한다. YCSB의 소수 hot plan/높은 동시성은 clone 수와 state 분리 효과를 드러낼 수 있지만 plan이 단순해 복잡 plan의 대표성은 낮다. 구조적 목표의 타당성과 warm-hit CPU 비용은 별도로 판단한다.
- **규칙**: MEM-02/04/05, COH-04/12, ALLOC-01/08, PAR-10/14, SER-01~03, MEAS-01/04/06/07.

### P7. xcache 내부의 중복 문자열·clone 관측과 메모리 회계 보강

- **현재 증거**: xcache는 entry `mem_size`, global cache/clone usage를 추적하고 문자열/clone capacity를 계산한다(`xasl_cache.c:501-525,1984-2043`). clone pool은 mutex 아래 1→2배 capacity 성장한다(`:2331-2373`). 그러나 감사한 경로에는 clone hit/miss와 descriptor/parser retained bytes의 통합 관측이 없다.
- **경계**: 구조 변경 전 plan key별 `{stream bytes, immutable candidate bytes, cached/in-use clone count+arena bytes}`, session별 `{handle count, SQL bytes, parser/PT bytes, metadata bytes}`를 노출한다. 측정 자체는 공유 설계와 독립적이다.
- **위험**: hot global atomic counter를 매 execute 추가하면 GLOB-09/PAR-01 비용. 기존 perfmon shard 또는 sampling/debug-only 계측을 사용한다.
- **메모리/YCSB**: P1/P3/P4/P6의 실제 우선순위를 정하는 필수 증거다. connection 수와 statements/connection을 독립 sweep해야 `O(S×K)`를 확인할 수 있다.
- **규칙**: MEAS-01/06/07, GLOB-09, PAR-01.

## 3. 우선 검증 행렬

### 실제 YCSB JDBC 보유 모델

`~/dev/cubrid-perftools-internal/ycsb`의 현재 harness를 읽은 결과, 추정이 아니라 다음을 확정할 수 있다.

- YCSB는 thread마다 `DBFactory.newDB`로 별도 `JdbcDBClient` 인스턴스를 만든다(`ycsb/core/.../Client.java:838-865`). 각 client의 `init`은 URL(shard)마다 connection 하나와 인스턴스별 `cachedStatements` map을 만든다(`ycsb/jdbc/.../JdbcDBClient.java:169-226`). 따라서 단일 shard에서는 thread 수와 server session 수가 함께 증가한다.
- statement key는 `(operation type, tableName, numFields, shardIndex)`이고 enum은 INSERT/DELETE/READ/UPDATE/SCAN 다섯 종류다(`JdbcDBClient.java:60-132`). 각 operation의 첫 호출이 `Connection.prepareStatement`하고 map에 넣은 뒤 cleanup까지 유지한다(`:239-314,317-467`). READ SQL은 `SELECT * ... WHERE YCSB_KEY = ?`, UPDATE/INSERT는 field 수에 따라 shape가 달라진다.
- 따라서 단일 table·단일 shard·고정 field count의 정상 transaction workload는 활성 operation 종류당 thread마다 handle 하나를 장기 보유하는 구조다. 정확한 live 수는 workload의 operation mix에 따라 최대 다섯 종류이며, 실행하지 않은 operation은 생성되지 않는다. shard가 여러 개면 key에 shard index가 들어가 해당 shard를 실제 방문한 operation별로 늘어난다.
- 이 harness는 P1/P2/P3/P4의 `sessions × active statement shapes` retained duplication을 직접 노출한다. 반대로 statement churn은 거의 없으므로 prepare CPU 측정에는 cold-init 구간을 별도로 잡아야 한다. P6는 같은 소수 plan을 여러 thread가 동시 실행하므로 clone/state scaling을 노출한다.

| 질문 | 최소 측정 |
|---|---|
| YCSB가 P1/P4를 노출하는가 | driver/CAS의 live handle 수, unique canonical SQL 수, prepare requests, xcache hit/miss, connection당 statement 수 |
| retained memory 지배항은 무엇인가 | 동일 workload 안정화 후 session별 SQL/DB_SESSION parser arena/PT/type metadata bytes와 process xcache stream/clone bytes; S와 K를 각각 sweep |
| P6의 구조적 메모리 상한 | plan별 stream size, clone arena size, cached clone count, peak in-use clones; plan shape별 분포 |
| CPU 기회도 있는가 | prepare를 parse/name/semantic/optimizer/XASL-build/pack/cache-insert로 분해; execute는 clone hit/miss와 unpack 시간 분리 |
| tail/경합 | throughput과 p50/p95/p99, MAD/표준편차; clone mutex wait, allocator/atomic counts를 절대값과 rate 함께 기록 |

벤치는 YCSB harness를 유지한다. 메모리를 (1) server boot/접속 전, (2) 모든 thread init 후·statement 생성 전, (3) operation 종류별 first prepare 직후, (4) warm steady state, (5) client cleanup 후에 찍는다. thread 수를 동일한 workload/config에서 sweep하고, workload mix를 A(READ+UPDATE), C(READ-only)처럼 고정해 active statement shape 수를 함께 기록한다. 별도 복잡 plan은 구조 크기 대표성 보조일 뿐, 주 판정은 YCSB로 한다. warm throughput 한 레그만으로는 cold prepare CPU와 retained component 귀속을 알 수 없다. 결과는 반복 median과 dispersion을 보고하고(MEAS-04/07), rate와 absolute count를 함께 둔다(MEAS-06). 코드 변경 A/B에서는 hot symbol layout gate도 필요하다(MEAS-08).

## 4. 감사 결론과 범위 한계

1. prepared statement를 공유 객체로 만드는 가장 직접적인 경계는 P1이다. 현 `T_SRV_HANDLE` 전체 공유가 아니라 descriptor와 execution handle을 분리해야 한다.
2. 메모리 목표에는 P2 SQL, P3 metadata, P5 retained replan tree도 포함해야 한다. 어느 항목이 지배적인지는 현재 숫자가 없다.
3. parser/PT tree 자체 공유(P4)는 MOP와 in-place mutable state 때문에 P1보다 큰 별도 컴파일러 표현 작업이다.
4. XASL stream 제거는 cache 제거와 같은 일이 아니다. P6의 native immutable plan + execution state 분리가 내부 representation serialization을 없애는 방어 가능한 구조적 경로다. wire/persistent codec은 실제 경계에 남긴다.
5. 이 감사가 mutable XASL write를 전수 증명하지는 않는다. `qexec_clear_xasl`과 모든 executor/parallel write site를 기계적으로 분류하는 후속 inventory가 P6의 첫 gate다.
