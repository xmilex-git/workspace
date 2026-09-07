# 공유 준비 객체 세대의 schema/auth/transaction 무효화 감사

이 문서는 정적 조사 당시의 사실·대안을 보존한다. 현재 결정은 [최종 판정](../candidate-disposition.md)과 [브레인스토밍](../optimization-brainstorm.md)을 따른다.

대상 frozen `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`, read-only current-code 확인이다. 서로 다른 DB user 간 공유는 하지 않는다는 전제에서도 같은 user의 권한·그룹·owner가 다른 세션에서 바뀔 수 있으므로 auth freshness는 남는다.

## 1. DDL과 transaction-local metadata

DDL 편집은 committed catalog를 바로 대체하지 않고 세션 workspace의 `SM_TEMPLATE/SM_CLASS`를 바꾼다. `install_new_representation`은 attribute id/storage order를 만들고, 필요하면 old instances를 flush/decache한 뒤 disk structures를 이전하고 trigger/descriptor cache를 무효화하고 template를 class object에 설치한 다음 class MOP를 다시 dirty로 만든다(`src/object/schema_manager.c:12428-12603`). 새 representation이면 session statistics/histogram cache도 버린다(:12582-12595). 이 함수 주석의 “commit operation”은 in-memory schema edit의 atomic install을 뜻하며 DB commit publish가 아니다. 실제 commit은 먼저 schema/view cache를 비우고(`transaction_cl.c:320-323`) dirty workspace를 flush한 뒤 server transaction commit으로 간다(:293-304).

따라서 자기 transaction의 미커밋 DDL로 compile한 native plan은 process 공유 generation에 publish하면 안 된다. 같은 transaction에는 dirty `SM_CLASS`가 우선 보이지만 다른 세션은 committed catalog만 봐야 한다. 안전한 분류는 `(A) committed schema snapshot에서 compile → commit-visible shared candidate`, `(B) dirty/new/deleted class MOP 또는 transaction-local classname을 참조 → session/transaction-private generation`이다. B는 commit 뒤 새 committed epoch에서 재compile해야 하며, abort 시 폐기한다.

commit과 full abort는 `sm_transaction_boundary`를 호출해 descriptor와 모든 resident virtual-query cache를 버린다(`transaction_cl.c:320-323,465-473`; `schema_manager.c:2107-2127`). savepoint rollback도 먼저 같은 boundary를 호출하고, 어떤 object/lock이 되돌려졌는지 client가 모르므로 workspace hints/locks를 다시 검증하게 만든다(`transaction_cl.c:1217-1268`). server는 modified-class registry에 class OID와 last modified LSA를 보관하며, sysop abort/savepoint rollback에서 해당 LSA 이후 `heap_classrepr`를 decache한다(`transaction_transient.cpp:127-136`; `log_manager.c:4105-4112,5162-5169`). transaction cleanup은 modified class 각각에 대해 partition cache, 관련 XASL, filter predicate cache를 제거하고 transient classname도 정리한다(`log_manager.c:5131-5179`).

공유 generation의 correctness epoch는 단일 `schema_id` 정수만으로 충분하다고 아직 증명되지 않았다. 현행 freshness 축은 class-record CHN, `SM_CLASS.repid`, session local/global schema versions, modified-class OID closure, transaction-local dirty state다. view cache는 local/global schema id와 snapshot version을 저장하며 mismatch면 재생성한다(`schema_manager.c:6772-6812,6936-7028`). CHN은 class record 내용 freshness, repid는 row physical representation, local schema version은 session parse/view cache invalidation이므로 서로 대체하지 않는다.

## 2. related-object closure와 실행 직전 검증

server XASL cache entry는 compile 시 전달된 모든 related class OID, required lock, tcard를 복사해 보관한다(`src/query/xasl_cache.c:1464-1515,1585-1586`). `xcache_remove_by_oid`는 이 배열에 OID가 하나라도 있으면 entry를 invalidate한다(:2045-2086). DDL cleanup이 이 API를 호출하므로 공유 prepared/native-plan generation도 최소한 **동일하거나 더 넓은 dependency closure**를 가져야 한다. base table만 기록하면 view expansion, inherited class, partition child, trigger/routine가 참조하는 object 변경을 놓친다.

현행 XASL acquire는 entry를 실행에 넘기기 전에 related objects 전부에 lock을 획득한다. 주석은 lock 없이 validity를 보장할 수 없고 SCH_M_LOCK 보유자가 invalidate할 수 있으므로 “locks first, then validity check”라고 명시한다(`xasl_cache.c:1035-1067`). shared SessionHandle/ExecutionState도 같은 안전 경계를 유지해야 한다: generation pin → dependency locks/epochs revalidate → auth revalidate → ExecutionState 생성/파라미터 bind → 첫 side effect. mismatch는 **첫 row mutation, sequence consumption, external method/trigger 호출 전에만** private recompile/retry할 수 있다. side effect 후 stale을 발견하면 자동 retry는 중복 효과 위험 때문에 금지해야 한다.

## 3. GRANT/REVOKE, group, owner

class GRANT는 authorization object를 update-lock/dirty로 만들고 grant row/set을 바꾼 뒤 해당 session의 class auth cache에서 모든 cached user slot을 invalid로 만든다(`authenticate_grant.cpp:120-300`). group grant는 member closure를 즉시 계산하지 않고 class의 모든 user cache를 무효화하는 이유가 코드에 명시돼 있다(`authenticate_cache.cpp:675-716`). GRANT도 local schema version을 bump한다(`authenticate_grant.cpp:289-300`). partition class는 child별 recursive grant를 system savepoint 아래 수행하고 실패하면 rollback한다(:133-160,304-308).

REVOKE는 grant chain을 수집해 affected grantees로 propagate한 뒤 local auth cache를 reset하고 local schema version을 bump한다(`authenticate_grant.cpp:657-703`). SERVER_MODE에서는 그것만으로 다른 세션 prepared plan이 계속 실행할 수 있어 `sm_touch_class`로 class CHN/schema-change machinery와 XASL invalidation을 유도한다는 현재 주석/코드가 있다(:705-716). partition revoke 실패도 system savepoint로 되돌린다(:725-733). 따라서 같은 DB user끼리만 plan을 공유해도 다른 DBA/session의 REVOKE commit 후 stale allow를 재사용하지 않도록 class/auth epoch 확인이 필요하다. 반대로 미커밋 REVOKE를 다른 session에 먼저 적용하면 isolation을 깨므로 process epoch publish는 commit-visible 시점이어야 한다.

procedure auth도 별도 cache를 갖고 GRANT에서 `reset_cache_for_user_and_procedure`와 local version bump를 수행한다(`authenticate_grant.cpp:456-462`; cache closure `authenticate_cache.cpp:719-747`). REVOKE procedure 쪽에는 현재 `reset_cache_for_user_and_procedure`가 주석 처리된 site가 보인다(`authenticate_grant.cpp:892`)고 grep으로 확인했으나 그 주변 전체 semantic path는 이번 제한 시간에 확정하지 않았다. shared native plan 정책은 이 현행 공백을 안전하다고 가정하면 안 되고 routine OID/auth generation을 dependency에 포함해야 한다. login/current user 변경도 vclass cache를 위해 local schema version을 bump한다(`authenticate_context.cpp:681-687`). owner 변경은 class/routine 의미와 authorization 결과를 동시에 바꾸므로 schema dependency와 auth dependency 양쪽 epoch를 갱신해야 한다.

## 4. view, trigger, routine dependency

view parse cache는 `SM_CLASS.virtual_query_cache`에 붙고 transaction boundary마다 전부 free된다(`schema_manager.c:2055-2074,2117-2125`). local/global schema version과 snapshot version이 key 일부다(:6936-7028). 공유 generation은 expanded view가 참조한 leaf class뿐 아니라 view OID 자체와 nested views를 closure에 넣어야 한다. view owner/current-user auth semantics 때문에 다른 DB user 공유 금지는 필요하지만 충분하지 않다. 동일 user의 groups/owner/auth catalog가 바뀌어도 다시 검증해야 한다.

DDL에서 제거된 attribute의 trigger schema cache는 target class에 직접 정의된 trigger만 골라 invalidate한다(`schema_manager.c:12361-12425`), representation install은 이를 실행한다(:12560-12565). 실행 plan이 trigger 존재/부재 또는 target column shape에 의존하면 class OID만으로 현행 cleanup에 걸릴 수 있지만, trigger definition/status/action 변경과 routine body 변경까지 closure가 완전한지는 별도 전수 검증이 필요하다. 안전 기본은 trigger OID와 trigger가 호출하는 routine/class dependency를 explicit generation dependency로 기록하는 것이다. 실행 시 trigger/routine 호출이 시작된 후 stale 발견은 retry 불가 side-effect 경계다.

## 5. correctness epoch와 statistics epoch 분리

statistics 변화는 결과 정합성을 바꾸지 않고 plan quality만 바꾼다. 현행 XASL cache는 related object의 stored tcard와 catalog page count를 비교해 큰 변화면 “request recompile” flag를 건다(`xasl_cache.c:2689-2740`). 이는 DDL/REVOKE처럼 즉시 실행 금지하는 correctness invalidation과 다르다. shared generation에는 최소 두 축이 필요하다.

- **correctness epoch:** class/view/partition/trigger/routine shape, CHN/repid, owner/auth/group closure. mismatch면 실행 전 반드시 reject/recompile.
- **statistics epoch:** cardinality/histogram timestamp. mismatch는 policy에 따라 background/next-use reoptimize할 수 있고 기존 plan 실행 자체는 허용 가능하다.

두 epoch를 하나로 합치면 stats 갱신마다 공유 plan을 몰아내어 churn을 만들거나, 반대로 correctness 변경을 advisory recompile로 잘못 취급할 위험이 있다.

## 정책 선택 전에 남은 사실 확인

- modified-class `xcache_remove_by_oid` closure가 view/trigger/routine의 간접 dependency를 모두 포함하는지 compiler의 `class_oids` 생산 경로를 전수하지 않았다.
- `sm_touch_class`가 REVOKE commit/abort 각각에서 CHN을 언제 publish하는지 locator/log tail까지 완전 추적하지 않았다. 현재 코드는 다른 session invalidation을 의도함은 명확하지만 process shared auth epoch 설계의 publish point로 바로 재사용할 수 있다는 판정은 아니다.
- owner/group membership 변경의 모든 entry point와 procedure REVOKE cache 경로를 전수하지 않았다.
- savepoint rollback 뒤 이미 process cache에 publish된 candidate를 회수하는 API는 현재 설계에 없으므로, transaction-private compile 결과의 pre-commit publish 금지가 가장 단순한 correctness boundary다.
- 실행/TSAN/격리 수준별 query는 수행하지 않았다.
