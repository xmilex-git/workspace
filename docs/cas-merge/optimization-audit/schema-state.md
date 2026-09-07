# 스키마·워크스페이스·도메인·권한·세션 상태 감사

이 문서는 정적 조사 당시의 사실·대안을 보존한다. 현재 결정은 [최종 판정](../candidate-disposition.md)과 [브레인스토밍](../optimization-brainstorm.md)을 따른다.

## 범위와 기준

- 감사 대상은 동결 엔진 `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`이다. 비교 기준 upstream은 `e374c7a24c46449c3f79e9413a6f4ff3d23b16c2`이나, 아래 행 번호와 판정은 모두 동결 스냅샷 현재 코드에서 다시 확인했다.
- CAS 통합 이전의 프로세스 전역이 통합 뒤 세션 상태가 된 구조를 `client_session_context`, workspace/MOP, `SM_CLASS`, 도메인, 인증, 트리거/뷰, 서버 `SESSION_STATE`, quick-fit/AREA까지 훑었다. prepared/XASL, PL/transport/DB_VALUE 내부는 소유 작업자의 범위라 인터페이스만 확인했다.
- 이 문서는 구현안이나 성능 수치를 약속하지 않는다. 측정 자료가 없으므로 속도 개선은 가설이며, 구조적 중복과 메모리 상한/공식만 제시한다(MEAS-01/04/06/07). YCSB에서 실행 빈도가 낮다는 이유로 메모리 목표를 기각하지 않는다.

## 현재 소유권 지도

`SESSION_STATE`가 서버 세션의 장수명 루트이고(`src/session/session.c:123-155`), 그 안의 `csc_p`가 folded client-half 상태를 소유한다. `client_session_context`는 bracket 전체를 `bracket_mutex`로 직렬화하며(`src/object/client_session_context.hpp:61-68`), auth/workspace/schema/trigger를 한 덩어리로 둔다(:70-82). 세션 종료는 `session_state_uninit`이 `csc_retire_and_delete`를 호출한 뒤 서버 세션 변수·prepared statement·query·session parameter를 해제한다(`src/session/session.c:353-433`). client-half 내부 해제 순서는 method/label → `sm_final` → query results → `ws_final` → MOP 도메인이다(`src/object/client_session_context.cpp:213-268`). 이 순서는 포인터 의존 때문에 계약이다.

## 후보별 감사

### S1. `client_session_context`의 고정 상태 묶음

- **현행/수명:** `authenticate_context`, `ws_context`, `sm_context`, `tr_context`와 여러 소형 카운터, plan dump, label table 등이 세션마다 존재한다(`client_session_context.hpp:61-162`). legacy CAS에서는 프로세스 전역이 사실상 한 세션 전용이었다. 통합 후 worker가 세션 고정이 아니고 OOB 요청도 다른 worker에 올 수 있어 bracket 직렬화가 필요하다(:64-68).
- **공유 경계:** 카운터, 사용자 신원, transaction/schema/trigger 상태는 값이 달라 공유할 수 없다. 하지만 컨텍스트 안의 포인터가 가리키는 불변 메타데이터까지 세션별 복제할 필요는 없다. 장기 경계는 `session-local overlay + process-wide immutable generation`이다.
- **정합 조건:** 세션 종료와 동시 접근, callback 종료, DDL rollback 중 overlay 생존을 bracket/ref-pin으로 보장해야 한다. mutex 제거는 별도 동시성 재설계 없이는 불가(COH-01, COH-12).
- **크기 공식/YCSB:** `Nsession × sizeof(client_session_context)`가 고정항이고 lazy 포인터 대상이 가변항이다. 실제 `sizeof`와 활성 세션 수는 측정 전 숫자를 만들지 않는다. YCSB는 많은 장수 연결에서 고정항을 그대로 노출하지만 카운터 자체의 실행 속도 이득은 작다.

### S2. MOP 해시 테이블과 classname cache

- **할당/해제:** `WS_MOP_TABLE_ENTRY{head,tail}`(`src/object/work_space.h:445-453`) 배열을 `ws_init`이 `sizeof(entry) × ws_Mop_table_size`로 malloc한다(`src/object/work_space.c:2415-2443`). SERVER_MODE 기본 미지정 시 파라미터 최솟값을 택한다(:2417-2427). classname hash는 세션마다 256 bucket으로 만든다(:2457-2464). `ws_final`이 classname hash, resident list, 모든 bucket MOP, lea heap 순으로 해제한다(:2540-2566).
- **왜 세션별인가:** MOP는 object pointer, dirty/lock/chn, resident/commit 연결과 owning workspace를 구성하는 mutable identity map이다(`work_space.h:458-490`). 미커밋 객체와 DDL을 다른 세션에 보이면 안 된다.
- **기회:** (a) 빈/저사용 세션의 테이블을 첫 MOP까지 lazy allocate, (b) bucket 배열을 실제 resident 수에 맞춰 grow, (c) classname의 committed `name→OID`는 process 공유 generation으로 두고 세션 hash는 uncommitted rename/create/drop overlay만 보관하는 방안을 검토할 가치가 있다. 세션 간 MOP 자체 공유는 금지한다.
- **정합 조건:** DDL rename/drop, abort/savepoint에서 overlay가 이전 generation을 가려야 하고, commit publish는 원자적 generation 교체여야 한다. REVOKE는 이름 캐시와 별개지만 동일 class generation 무효화를 요구한다. 비용은 `Nsession × (B × sizeof(WS_MOP_TABLE_ENTRY) + Hclassname) + ΣMOP`이며 B와 hash 내부 바이트는 런타임 계측이 필요하다. YCSB는 테이블 수가 작아 lazy/grow가 메모리에 직접 노출되며, lookup 속도는 load factor 측정 없이는 약속 못 한다(ALLOC-01/02, DS-01, MEAS-01).

### S3. resident/dirty MOP와 per-session `SM_CLASS`

- **내용/수명:** `SM_CLASS`는 속성·상속·메서드·query_spec·통계·owner·auth/virtual/trigger/constraint/partition cache를 한 객체에 둔다(`src/object/class_object.h:737-814`). 속성 하나도 두 `DB_VALUE` 기본값, domain, class MOP, trigger cache 등을 가진다(:393-471). 생성 시 캐시 포인터를 NULL로 초기화(`class_object.c:6880-6929`), 해제 시 모든 연결 리스트/배열과 virtual/trigger/auth/constraint cache를 재귀 해제한다(:6949-7019).
- **옛/현재 이유:** CAS별 object graph는 로컬 MOP, 현재 사용자, 미커밋 DDL과 자연스럽게 결합됐다. 현재도 `sm_get_class_repid`가 MOP fetch와 권한 검사를 거쳐 세션 `SM_CLASS.repid`를 읽는다(`schema_manager.c:6333-6357`). 따라서 전 객체를 그대로 공유하면 transaction-local schema view가 깨진다.
- **핵심 de-dup:** committed schema의 불변 shape(속성 이름/id/order/type, repid, index/BTID, partition facts, query-spec 원문/정규형)를 OID+schema-generation 키의 process-wide immutable descriptor로 만들고, `SM_CLASS`는 MOP/owner/auth/dirty template/caches의 세션 overlay로 축소하는 방향이 가장 큰 구조적 후보다. 단번에 OR_CLASSREP로 치환하기보다 접근자 뒤에서 단계적으로 descriptor를 쓰는 경계가 현실적이다.
- **정합 조건:** DDL은 기존 `SM_TEMPLATE→install→flush`의 미커밋 버전을 해당 세션에 우선 노출하고 abort/savepoint가 overlay만 폐기해야 한다. commit 후에만 새 generation publish, DROP은 기존 pin이 끝난 뒤 reclaim한다. REVOKE는 shape generation과 auth generation을 분리한다. prepared 재검증은 repid/CHN/generation과 맞물려야 한다. 메모리 절감 공식은 `Σclass [ (Nsessions_touching(class)-1) × immutable_payload(class) ] - overlay/pin overhead`; 실제 payload는 `classobj_class_size`와 allocator 계측으로 구해야 한다. YCSB는 소수 테이블을 모든 세션이 반복 touch하므로 중복 제거율은 높을 가능성이 있지만, compile/fetch 비중과 latency 개선은 측정 대상이다(MEM-01/05, COH-05, ALLOC-05).

### S4. domain interning

- **이미 공유됨:** process domain AREA는 `area_create("Domains", sizeof(TP_DOMAIN),1024)`로 생성된다(`src/object/object_domain.c:668`). 현재 코드는 콘텐츠에 MOP가 없는 도메인을 process list에 남기고, MOP 또는 재귀 setdomain에 MOP가 있는 것만 세션 list로 라우팅한다(:1893-1951, :3110-3128). `TP_SESSION_DOMAINS`는 타입별 head 배열이며 lazy calloc한다(:1902-1961), teardown은 모든 노드를 uncache/free한다(:1964-1999).
- **왜 남았나:** process cache에 session MOP를 넣으면 workspace 종료 뒤 UAF가 된다(:1894-1901). 타입 전체를 세션화하면 built-in domain의 packed XASL 형식이 달라지는 과거 결함도 코드가 명시한다(:1935-1941).
- **기회/경계:** 현 content-based split은 올바른 최소 경계다. 추가 감축은 `class_mop`을 process-stable OID+generation handle로 대체할 수 있는 domain만 canonicalize하는 것이다. MOP가 필요한 client API는 session wrapper를 유지한다. 실패 시 process cache fallback도 금지되어 있다(:3113-3121).
- **정합/YCSB:** DROP/DDL 뒤 generation mismatch, OID reuse, nested setdomain 전부 검증해야 한다. 절감은 `Σsession unique_MOP_domains - Σprocess unique_(OID,generation)_domains`; YCSB 단순 타입은 이미 process built-in을 맞힐 가능성이 높아 추가 이득은 제한적일 수 있다(COH-05, DS-03, ALLOC-05).

### S5. authorization context와 class auth cache

- **현행:** 전역처럼 보이는 `Au_user`, `Au_cache` 등은 session `authenticate_context` 접근 매크로다(`src/object/authenticate.h:54-77`). class별 `SM_CLASS.auth_cache`는 해당 세션의 `authenticate_cache` class list에 연결되고 해제된다(`authenticate_cache.cpp:314-345`). lookup은 현재 사용자에 따라 bit를 얻고 미스 시 update한다(`authenticate_access_class.cpp:880-921`). GRANT/REVOKE는 그룹 구성 때문에 해당 class의 모든 cached user slot을 무효화한다(`authenticate_cache.cpp:675-716`); transaction boundary에서는 전 class/procedure cache를 invalid로 만든다(:749-785).
- **왜 세션별인가:** 판정은 current user/group, disable flag, transaction visibility에 민감하다. `SM_CLASS*`와 MOP가 키이므로 그대로 process 공유할 수도 없다.
- **기회:** 권한 카탈로그의 committed grant graph를 process-wide immutable `auth_generation`으로 공유하고, `(auth_generation,user_oid,class_oid,auth_kind)` 판정 캐시를 read-mostly로 공유할 수 있다. current-user와 uncommitted GRANT/REVOKE는 session overlay에 남긴다. 이는 중복 판정 데이터를 줄이지만 공유 캐시 locking/eviction이 YCSB SELECT hot path를 느리게 할 수 있어 per-session tiny front cache나 generation-tagged lock-free read를 비교해야 한다.
- **정합:** GRANT/REVOKE commit 전 자기 변경 가시성, rollback/savepoint 복원, group membership 변경의 전이 폐쇄, owner/system-class 규칙, OID reuse를 포함한다. REVOKE가 commit되기 전 다른 세션이 새 권한을 보거나 commit 뒤 stale allow를 쓰면 안 된다. 공식은 `Σsession auth_entries - unique(user,class,generation)`이지만 entry 크기/적중률을 측정해야 한다(PAR-10, COH-05/10, GLOB-02).

### S6. trigger state/cache

- **현행:** `tr_context`에는 실행 깊이/stack/deferred actions뿐 아니라 user/uncommitted trigger list, schema cache, object map이 모두 세션별이다(`src/object/trigger_manager.h:224-252`). 이는 trigger cache가 MOP를 보유하기 때문이라고 현재 코드가 명시한다(:225-227). `SM_CLASS.triggers`와 attribute trigger cache도 존재(`class_object.h:466,793`). 상태 변경 시 class flag를 invalid로 바꾼다(`schema_manager.c:4745-4766`).
- **분리 기회:** 실행 stack, deferred list, uncommitted trigger, enable/trace flag는 반드시 session-local이다. committed trigger 정의(이름, event, target OID/attribute id, condition/action의 immutable compiled-or-source representation)는 class generation별 process 공유 후보이고, 세션 schema cache는 stable trigger IDs와 local overlay만 가진다.
- **정합:** CREATE/ALTER/DROP TRIGGER와 DDL target 변경이 commit 전 자기 세션에 보이고 rollback 시 복구되어야 한다. 실행 중 pin된 정의는 DROP commit 뒤에도 안전하게 끝나야 하며, `Au_user`별 실행 권한과 deferred trigger transaction ordering은 공유하지 않는다. 메모리는 `Σsession committed_trigger_payload touched - unique committed payload`; YCSB core는 보통 trigger가 없어 컨텍스트 고정항/빈 hash lazy allocation만 노출된다. trigger 사용 변형은 write latency를 따로 측정한다(MEM-05, COH-05, ALLOC-02).

### S7. virtual-query/metadata caches와 descriptors

- **현행:** `SM_CLASS.virtual_query_cache`는 parser context 포인터이고 local/global schema id와 snapshot version을 함께 보관한다(`class_object.h:781-803`). class 해제 때 parse cache를 해제한다(`class_object.c:6999-7002`). commit/abort 경계마다 descriptors와 모든 resident view cache를 비운다(`schema_manager.c:2107-2127`), descriptor는 attribute/method 포인터가 stale해질 수 있어 class edit/commit 때 invalid된다(:7233-7269).
- **왜 세션별인가:** parse tree가 MOP와 schema/current-user resolution을 품고, transaction-local DDL 및 auth에 민감하다. metadata rows도 snapshot에 따라 달라질 수 있다.
- **기회:** view SQL 원문/tokenized immutable syntax와 catalog metadata의 schema-only projection은 process 공유하고, name resolution/auth/MOP binding parse tree는 session/transaction overlay로 유지한다. descriptor도 `(class OID, schema generation, attr id)` stable key로 바꾸기 전에는 포인터 graph 공유가 불가하다.
- **정합/YCSB:** nested view generation, current schema, snapshot, DDL rollback, owner/REVOKE를 cache key 또는 binding 단계에서 반영한다. YCSB base tables에서는 view cache가 거의 노출되지 않지만 모든 세션의 class descriptor 중복은 남는다. 속도 주장은 view workload 없이는 하지 않는다(MEM-05, PHYS-05, MEAS-01).

### S8. 서버 session variables와 session parameters

- **현행:** `SESSION_STATE`는 변수 linked list와 `SESSION_PARAM*`를 별도로 소유한다(`src/session/session.c:123-149`). 변수는 최대 20개이며(`:81-83`), 각 노드가 name, heap `DB_VALUE`, next를 가진다(:92-98); 추가는 선형 탐색 후 3개 할당을 수행(:1153-1235), 조회도 선형 탐색 후 value clone이다(:2107-2135). no-copy 조회는 folded client bracket의 독점 소유에서만 허용한다(:2162-2203). parameter array는 세션에 설치되고(:1717-1759), ID→전역 index로 O(1) 접근한다(:2834-2869), 종료 때 `sysprm_free_session_parameters`로 해제한다(:428-431).
- **DB/client 중복:** `client_session_context`에도 optimizer-level override와 db connection identity가 있다(`client_session_context.hpp:84-135`). 이는 같은 값의 단순 복제라기보다 client compatibility 상태와 server session parameter의 서로 다른 API 경계다. 동일 parameter가 양쪽에 실제로 저장되는지는 parameter별 write/read trace가 필요하다.
- **기회:** 변수는 값이 세션 의미 그 자체라 cross-session 공유 대상이 아니다. 다만 이름은 intern 가능하고, 20개 상한에서는 small-vector/inline nodes로 할당 2~3회를 없앨 후보가 된다. parameters는 process default blob + session delta bitmap/compact overrides로 바꾸면 동일 기본값 배열 중복을 줄일 수 있다. optimizer override도 이 delta에 합쳐 단일 SSOT가 될 후보다.
- **정합/YCSB:** SET/RESET 즉시 가시성, no-copy 포인터 안정성, timezone/optimizer가 compile/execute 결과에 미치는 영향, session migration을 보존한다. 공식은 `Nsession × full_session_param_blob - Σsession override_bytes`; 변수는 `Σ(name+DB_VALUE payload+node)`이다. YCSB가 parameter를 거의 바꾸지 않으면 default+delta의 메모리 이득이 크고 변수 lookup 속도는 기본 workload에서 노출되지 않는다(ALLOC-01/04, STR-03, DS-01).

### S9. quick-fit/LEA heap와 AREA

- **현행:** SERVER_MODE quick-fit heap ID는 owning session workspace에서 bracket으로 찾는다(`src/object/quick_fit.c:38-44`). `db_create_workspace_heap`이 LEA heap 등록, `db_destroy_workspace_heap`이 unregister한다(:80-115). 이는 다른 worker가 같은 세션을 처리해도 올바른 heap으로 free하기 위한 ALLOC-08 경계다. 반면 object-list AREA는 process singleton으로 한 번 생성(`work_space.c:3921-3941`)되고 alloc/free한다(:4873-4905); domain/schema template 등도 process-shared AREA를 사용한다.
- **옛/현재 이유:** legacy CAS의 heap은 process/session 일치였다. 통합 뒤 session-local heap은 bulk teardown과 MOP pointer lifetime을 보존하며, AREA 공유는 fixed-size 노드 중복 allocator slab을 이미 제거한다.
- **기회:** 빈 세션의 LEA heap을 첫 workspace allocation까지 lazy create; immutable shared descriptor는 process allocator로 이동; session overlay는 arena/LEA에 남긴다. process AREA는 allocator contention과 cross-session cache locality를 계측한 뒤에만 sharding 여부를 결정한다. 공유 AREA를 세션별로 되돌리는 것은 메모리 목표에 역행한다.
- **정합/YCSB:** 어떤 allocator에서 생성됐는지를 type/owner에 고정하고 process object가 session heap을 가리키지 않게 한다. cross-thread free는 global/process allocator 또는 owning heap route를 지킨다(ALLOC-08). 공식은 `Nsession × LEA base/metadata + allocated chunks`; base 크기는 allocator 구현/런타임 RSS로 측정해야 하며 과거 문서의 숫자를 현행 실측으로 간주하지 않는다. YCSB 장수 연결 수에 선형인 floor라 우선 계측 후보다(ALLOC-03/05/08, PAR-11).

## 우선순위와 측정 제안

1. **메모리 계측부터:** 세션 생성 직후, 첫 SELECT, 첫 UPDATE, schema fetch 후에 category별 allocated/live/peak를 기록한다: MOP table, classname, LEA, SM_CLASS immutable/overlay 추정, auth, trigger, view, domain, session params. `N=1,10,100,...`에서 slope를 구한다. RSS만으로 allocator retained memory와 live bytes를 혼동하지 않는다.
2. **S3 immutable schema descriptor prototype 경계 검증:** 실제 공유 구현 전 read-only inventory로 `SM_CLASS` 필드 접근을 schema facts와 session/transaction facts로 분류한다. 가장 큰 구조적 중복 후보이나 correctness 반경도 가장 크다.
3. **저위험 구조 후보:** S2 MOP table/heap lazy init, S8 default-parameter+delta, 빈 trigger/object-map lazy init. 메모리 slope를 줄이는지 먼저 증명한다.
4. **속도 검증:** YCSB load/run에서 throughput만 보지 말고 p50/p95/p99, CPU, allocations, class/auth cache hit/miss와 absolute counts를 함께 비교한다. shared generation이 lock/HITM을 만들면 `perf c2c`로 확인한다(MEAS-06/07, COH-02, PAR-10/11).

## 결론

남은 per-session 상태를 통째로 process 공유하는 것은 맞지 않는다. 그러나 그것이 메모리 아키텍처 목표를 기각하지도 않는다. 가장 큰 경계는 **committed immutable schema/auth/trigger/view payload의 process generation**과 **MOP·current user·미커밋 DDL/GRANT/trigger·execution/deferred state의 session overlay**다. 현재 코드는 MOP 없는 domain과 fixed-size AREA에서 이미 이 원리를 부분 적용했다. YCSB에 가장 직접적인 후보는 모든 연결이 같은 소수 테이블을 touch할 때의 `SM_CLASS` immutable payload, per-session MOP table/LEA floor, unchanged session-parameter blob이다. 실행 속도 향상은 schema/auth fetch 또는 allocation이 profile에 나타날 때만 주장할 수 있다.

## 정직한 미확인 범위

- 빌드, 실행, RSS/heap/perf 측정은 하지 않았다.
- `classobj_class_size`가 연결된 모든 allocator payload를 완전히 합산하는지는 확인하지 않았다.
- upstream commit과의 전체 diff 및 각 후보가 fold에서 새로 생긴 정확한 commit은 추적하지 않았다. legacy CAS 필요성은 현재 주석과 소유권 구조로 검증 가능한 범위에서만 서술했다.
- metadata/system catalog 전 소비자, 모든 session parameter ID, trigger parser/action 내부, virtual-query parse tree 모든 MOP 필드는 전수 열거하지 않았다.
- prepared statement/XASL, PL/runtime transport, DB_VALUE representation은 다른 감사 범위이므로 중복 분석하지 않았다.
