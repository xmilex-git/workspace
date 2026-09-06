# S10 — class locator/CHN/copyarea와 server classrepr 감사

대상 frozen `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`, read-only 확인이다.

## 실제 current read chain

대표 compiler consumer는 `xasl_generation.c:5189`에서 `locator_fetch_class(class_, DB_FETCH_READ)`를 호출하고 auth/schema 경로도 같은 API를 쓴다(`authenticate_access_class.cpp:434-446`, `schema_manager.c:6394-6477`). `locator_fetch_class`는 class MOP에 맞는 lock을 계산하고 `locator_lock(...LC_CLASS, LC_FETCH_CURRENT_VERSION)` 뒤 `ws_find`의 세션 object를 반환한다(`transaction/locator_cl.c:2261-2322`). 따라서 hit 반환은 server record를 직접 참조하는 것이 아니라 이미 workspace가 소유한 `SM_CLASS*`다.

miss/lock-upgrade에서 `locator_lock`은 workspace object/lock을 검사해 skip 여부를 정한다(`locator_cl.c:637-660`, skip 계약 `:6724-6769`). server fetch가 필요하면 object CHN과 class CHN을 `ws_chn`에서 얻어(`:707-752`) `locator_fetch`를 호출한다(:787). SERVER_MODE의 `locator_fetch`는 socket pack/unpack을 하지 않고 `enter_server` 후 `xlocator_fetch`를 직접 호출한다(`communication/network_interface_cl.c:338-391`). 즉 fold 뒤 네트워크 직렬화는 사라졌지만 **RECDES bytes를 담는 LC_COPYAREA 생성과 disk→SM_CLASS 변환은 남아 있다**. “nested network serialization”으로 부르면 부정확하다.

`xlocator_fetch`는 처음 DB page 크기의 `LC_COPYAREA`를 allocate하고 부족하면 늘린다(`transaction/locator_sr.c:2486-2583`). `locator_lock_and_return_object`는 `locator_get_object(..., COPY, chn)`로 heap record를 copyarea의 RECDES에 복사한다(:2312-2338). CHN이 다르면 descriptor에 `LC_FETCH`, byte length/offset을 기록하고 root-class object면 `heap_chnguess_put`한다(:2170-2220). CHN이 같으면 content 없이 `LC_FETCH_VERIFY_CHN` descriptor만 만들 수 있고(:2224-2253), 반환 object가 0개면 copyarea 자체를 free한다(:2640-2648).

folded caller는 받은 copyarea를 `locator_cache`로 처리하고 즉시 free한다(`locator_cl.c:794-805`). class `LC_FETCH`는 `tf_disk_to_class`로 새 graph를 만든 뒤 `ws_cache`로 세션 MOP에 붙인다(:3323-3344). `tf_disk_to_class`는 RECDES buffer에서 repid/CHN을 읽고 `disk_to_class`로 `SM_CLASS`를 생성하며 이를 class fields/header에 저장한다(`object/transform_cl.c:4359-4424`). GC가 중간 MOP 포인터를 회수하지 못하게 caller가 즉시 `ws_cache`해야 한다는 수명 계약도 명시돼 있다(:4364-4374). CHN mismatch/decache-lock이면 instance locks를 비우고 다시 변환한다(`locator_cl.c:3346-3379`); verify descriptor의 CHN이 다르면 `ws_decache`한다(:3551-3562). dirty MOP는 cache overwrite에서 보호된다(`:3620-3634`).

## `heap_Guesschn`과 두 표현

client가 `CHN_UNKNOWN_ATCLIENT`를 보내면 server는 transaction index별 guess를 `heap_chnguess_get`으로 복원한다(`locator_sr.c:2324-2329`); 실제 class record를 보낸 뒤 `heap_chnguess_put`한다(:2189-2196). storage singleton은 1024 class entry(`HEAP_CLASSREPR_MAXCACHE`)와 transaction 수에 비례하는 bit matrix를 할당한다(`storage/heap_file.c:15505-15563`), transaction table 증가 때 matrix를 재할당한다(:15591-15643). 이것은 network가 없어진 뒤에도 client-cache protocol을 그대로 유지하는 retained structure다. 제거하려면 단순 delete가 아니라 같은-session workspace CHN 전달이 항상 정확하다는 증명, unknown caller 제거, transaction slot reuse/schema-change invalidation 대체가 필요하다.

server 실행용 `OR_CLASSREP`은 별도 process cache다. `heap_classrepr_get`은 class OID/repid로 cache를 pin하고 record miss에서 `or_get_classrep`으로 materialize한다(`heap_file.c:1946-1982,1997-2238`); 소비자는 `heap_classrepr_free`로 pin을 내린다(`:1585-1602`). DDL/recovery 측 invalidation은 `heap_classrepr_decache` entry point다(`:1512-1533`). 이것은 세션 `SM_CLASS`와 동일 객체가 아니다. 전자는 record layout, attributes/indexes/domain 등 server execution facts에 집중하고, 후자는 MOP, auth, view/query-spec, trigger, methods, transaction-local editing graph를 포함한다.

## 좁은 read-through 후보

전체 `SM_CLASS` 공유보다 먼저, 이미 server에 안정적으로 있는 committed facts를 OID+schema generation accessor로 읽는 후보가 있다.

- HFID/representation directory/repid: class record header 및 classrepr/catalog에 존재한다. compiler가 현재 `SM_CLASS.header`/`repid`만 읽는 접근자를 OID 기반 read-through로 바꾸면 이 필드 때문에 class 전체 fetch하는 경우를 줄일 수 있다.
- attributes의 id/storage order/domain/nullability와 index/BTID: `OR_CLASSREP`가 보유하며 server consumers가 이미 pin/free 계약으로 쓴다. compiler용 immutable projection을 별도로 제공할 수 있다.
- statistics: server catalog/statistics가 SSOT이고 `SM_CLASS.stats/histogram`은 lazy session cache다. generation-tagged read-only snapshot 후보이다.
- partition shape: server partition pruning cache/OR partition facts가 존재한다. 단 predicate/query semantic object와 transaction-local DDL은 overlay가 필요하다.

경계는 **SM_CLASS를 받은 뒤 같은 값을 다시 server에서 읽는 것**이 아니다. class materialization 전에 필요한 좁은 fact만 read-through하여 full LC_COPYAREA→`tf_disk_to_class`를 피할 수 있는 call site여야 이득이 있다. 현재 in-process `xlocator_fetch`도 heap record를 copyarea에 실제 복사하므로, 그런 miss에서만 allocation/copy/graph materialization을 제거한다(ALLOC-01/05, MEM-01/05). 이미 materialized `SM_CLASS` hit에는 추가 classrepr lock/pin을 넣으면 오히려 손해다(PAR-10).

## correctness와 미확인

DDL commit 전 자기 세션의 dirty `SM_CLASS/SM_TEMPLATE`가 committed projection보다 우선해야 하며 rollback/savepoint 뒤 overlay가 사라져야 한다. commit/drop/revoke는 schema generation, auth generation, prepared dependency invalidation을 구분한다. old projection은 pin이 끝날 때까지 reclaim하지 않고 OID reuse를 generation으로 막는다. CHN은 physical class record freshness이고 repid는 row representation이므로 둘을 하나의 version으로 가정하지 않는다.

빌드/실행/할당·copy byte 측정은 하지 않았다. `locator_cache` 전체 loop 및 모든 prefetch descriptor를 전수 기술하지 않았다. HFID/repid/index/stats/partition 각각의 compiler call site가 full fetch를 유발하는지 전수 분류하지 않았으므로 read-through는 후보이며 절감 보장이 아니다. `heap_Guesschn` unknown-CHN callers와 schema-change invalidation을 전수 추적하지 않아 제거 가능 판정도 하지 않는다.
