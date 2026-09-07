# 공유 준비 객체·native plan 무효화 감사

이 문서는 정적 조사 당시의 사실·대안을 보존한다. 현재 결정은 [최종 판정](../candidate-disposition.md)과 [브레인스토밍](../optimization-brainstorm.md)을 따른다.

- 대상: frozen engine `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`
- 전제: 수락된 3계층 = (1) DB user별 공유 immutable prepared/native plan, (2) session statement handle, (3) per-execution mutable state. DB user 간 공유하지 않는다.
- 방법: 현재 xcache/compile/retry/DDL/stats 코드를 읽었다. 정책 결정, 구현, 실행 측정은 하지 않았다.

## 1. 현재 xcache가 이미 제공하는 generation과 회수 계약

| 사실 | 근거 | 성격 |
|---|---|---|
| key lookup이 성공하면 lock-free hash가 entry fix count를 올리고 transaction을 끝낸다 | `xcache_find_sha1`, `src/query/xasl_cache.c:872-955`, 특히 `:893-907` | 메모리 안전/수명 |
| `XASL_ID`는 SHA1뿐 아니라 `time_stored` generation을 포함한다. 같은 SHA1의 새 entry여도 cached ID의 generation이 다르면 execute가 거부된다 | `xcache_find_xasl_id_for_execute`, `:969-1023` | 정확성. ABA/구 plan handle 차단 |
| execute는 관련 객체의 plan 요구 lock을 모두 얻은 뒤 deletion mark를 다시 읽는다 | `:1037-1090`, 관련 lock `:1047-1077`, mark 재검사 `:1079-1089` | 정확성. “lookup 시 살아 있었음”만으로 실행하지 않음 |
| delete mark는 신규 lookup을 막되 fix 중인 사용자의 메모리를 즉시 free하지 않는다. 마지막 `xcache_unfix`가 clone/list cache를 정리하고 hash erase한다 | `xcache_entry_mark_deleted :1289-1348`; `xcache_unfix :1182-1285` | 수명/동시성 |
| 실행 clone은 entry가 fix된 동안 사용되고 종료 시 먼저 `xcache_retire_clone`, 그 다음 unfix된다 | `src/query/query_manager.c:1639-1649`; retire `xasl_cache.c:2316-2388` | 수명. 새 native plan/state에도 같은 pin 범위 필요 |
| recompile은 old entry를 `TO_BE_RECOMPILED`로 claim하고 새 entry를 삽입한 뒤 old를 `WAS_RECOMPILED`로 바꾼다. 이미 fix한 사용자는 old를 계속 쓸 수 있고 마지막 unfix에서 제거된다 | `xcache_insert :1558-1570,1617-1676,1689-1757` | 기존 generation 교체/compile race |
| 동시 recompilers는 한 thread만 old entry를 claim하고 나머지는 loop+1ms sleep한다 | `:1566-1569,1693-1755` | 진행성/최적화. starvation/폭주 정책은 명시적이지 않음 |
| replan replacement는 old `time_stored`를 새 entry에 상속하여 이미 client에 캐시된 XASL_ID도 새 plan을 쓸 수 있게 한다 | `:1739-1745` | 의도적인 generation 예외. schema invalidation과 구분 필요 |

수락된 구조에 그대로 재사용할 수 있는 것은 `fix/generation/mark-deleted/last-unfix` 프로토콜이다. 새 shared descriptor는 자기 수명만 xcache pointer에 얹으면 안 된다. descriptor와 immutable native plan이 별도 객체라면 각각 generation 또는 하나의 원자적 version bundle, pin/ref 및 retire 상태를 가져야 한다.

## 2. 무효화 producer와 시점

### I1. schema/객체 변경 — 정확성 무효화

- class update/delete force는 레코드 변경 경로에서 `xcache_remove_by_oid`를 호출한다: `src/transaction/locator_sr.c:5671-5675,6294-6298`. synonym과 serial도 OID invalidation을 호출한다: `locator_sr.c:13949-13953`, `src/query/serial.c:1781`.
- transaction의 modified-class registry는 commit/abort/savepoint cleanup에서도 partition/filter/XASL cache를 비운다: `log_cleanup_modified_class`, `src/transaction/log_manager.c:5123-5179`. normal local commit은 commit log 기록과 lock release보다 앞서 `log_cleanup_modified_class_list`를 호출한다(`:5230-5271`). rollback/savepoint도 같은 cleanup을 타며 classrepr decache 범위가 다르다(`:5163-5179`, 호출 `:5336,5667`; sysop abort `:4091-4124`).
- 따라서 “DDL commit 순간에만 한번 invalidate”라고 단순화하면 현재보다 약하다. 현재는 force 시점과 transaction cleanup 시점 모두 producer가 있으며, uncommitted DDL의 자기 transaction visibility와 rollback 복원을 함께 다룬다.
- execute 쪽 class locks가 핵심이다. prepared execute는 관련 객체 lock을 취득하고 deletion mark를 재검사한다(`xasl_cache.c:1047-1090`). DDL의 schema lock과 이 lock의 충돌/순서가 새 실행 허용 시점을 결정한다. MVCC가 schema-plan 정합을 대신하지 않는다.
- 이미 fix하여 관련 lock까지 확보한 실행이 언제까지 old plan을 쓸 수 있는지는 lock mode와 DDL producer의 lock 취득 순서에 달렸다. current code가 fix count로 메모리를 살려 둔다고 해서 모든 old plan 실행을 의미상 허용한다는 뜻은 아니다. 새 정책은 “lookup”, “schema lock 획득”, “execution 시작” 중 linearization point를 정해야 한다.

### I2. REVOKE/권한 — 정확성 무효화

- 권한 검사는 compile-time이고, REVOKE는 현재 session auth cache/local schema version만 지우는 것으로 부족해 SERVER_MODE에서 `sm_touch_class`를 호출한다(`src/object/authenticate_grant.cpp:683-716`). `sm_touch_class`는 null class edit/finish로 schema machinery를 태운다(`src/object/schema_manager.c:15405-15434`).
- DB user 간 descriptor를 공유하지 않는 결정은 key/ownership을 단순화하지만 REVOKE 후 같은 user의 모든 shared descriptor를 invalidate해야 하는 요구는 남는다. GRANT/owner/change-rights도 동일 범주인지 producer 전수 감사가 필요하다.
- 새 descriptor가 xcache보다 오래 남아 metadata/compiled artifact를 제공하면 xcache OID invalidation만으로 부족하다. descriptor도 related-object OID dependency set 또는 xcache generation에 결합되어야 한다.

### I3. statistics/cardinality 변화 — 재최적화 정책

- xcache는 related object마다 compile-time `tcard`를 보유한다(`xcache_insert`, `xasl_cache.c:1498-1515`). `xcache_check_recompilation_threshold`가 주기적으로 catalog class info를 읽고 큰 page-count 변화 시 `RECOMPILED_REQUESTED`를 설정한다(`:2651-2746`). 이는 schema safety가 아니라 plan quality 정책이다.
- UPDATE STATISTICS는 catalog statistics/timestamp를 갱신하고 SCH_S lock을 해제한다(`src/storage/statistics_sr.c:83-132,430-489`). client half는 workspace를 flush한 뒤 update하고 cached stats/histogram을 버린다(`src/object/schema_manager.c:4246-4305`).
- 현재 retained-tree 주석은 statistics가 plan과 함께 invalidated된다고 전제하며 bind fingerprint가 없으면 unpeeked flag를 영구 clear한다(`src/compat/db_vdb.c:2248-2260`). 실제 invalidation producer/threshold의 정확한 결합은 별도 확인이 필요하다. UPDATE STATISTICS가 모든 dependent plan을 즉시 hard-delete하는지, threshold/next lookup에서 soft replan하는지 정책을 동일시하면 안 된다.
- statistics replan은 결과 의미를 바꾸지 않는다는 전제로 xcache가 result-cache ownership을 새 plan에 넘긴다(`xasl_cache.c:1621-1648`). schema/auth invalidation에서는 이 전제를 재사용하면 안 된다.

### I4. bind-sensitive/first-bind replan — session/execution overlay 정책

- first bind 또는 histogram fingerprint 변화가 post-transform kept tree에서 plan+XASL만 재생성한다(`db_vdb.c:2240-2283`). SQL-level PREPARE의 kept tree가 stale/cache-invalid errors를 받으면 제거하고 stored SQL을 full compile한다(`:2160-2207`).
- 현재 fingerprint와 `hv_pred_plan_unpeeked`는 session PT statement의 mutable state다. 3계층 구조에서는 shared descriptor에 쓰면 data race와 한 session의 bind가 다른 session의 선택을 고정한다. fingerprint/selection은 session handle 또는 execution state에 있어야 한다.
- 열린 구조 선택은 한 cache key에 plan variant를 하나만 둘지, bind bucket별 immutable variants를 둘지다. 후자는 variant cap/eviction과 statistics generation key가 필요하다.

### I5. session parameter/user key 변화 — 새 lookup, hard invalidation 아님

- alias key는 plan 영향 system parameters, current user OID, host-var count를 인쇄한다(`src/parser/parse_tree_cl.c:3068-3120,3164-3176`; 세션 read-through parameter 출력은 `src/base/system_parameter.c:12514` 이하).
- DB user 간 미공유 결정은 current user OID를 descriptor namespace의 1차 축으로 만들 수 있다. 세션 SET으로 key material이 바뀌면 기존 객체를 전체 invalidate하기보다 해당 handle이 새 key/generation을 resolve하는 방식이 자연스럽지만, key 목록 완전성은 정확성 조건이다.
- `include_oid`, updatable/holdable 중 compile shape에 영향을 주는 flags, query replacement identity도 descriptor key에 포함해야 한다. 실행-only 속성은 session handle/state에 남긴다.

## 3. retry/error 계약

| 신호 | 현재 처리 | 새 descriptor 계약 |
|---|---|---|
| `ER_QPROC_XASLNODE_RECOMPILE_REQUESTED` | RT/stat replan 요청. execute→prepare(no stream)→compile→replace protocol; `xcache_find_sha1 :850-869`, `db_vdb.c:2287-2320` | soft replan. single-flight 여부와 old-generation 사용 허용 정책 필요 |
| `ER_QPROC_INVALID_XASLNODE` | deleted/missing/generation mismatch/schema stale 등. db_vdb는 whitelist retry, CAS pooled statement는 `CAS_ER_STMT_POOLING`으로 driver reprepare 요청(`cas_execute.c:1246-1254`); execute-array는 1회 local recompile(`:2434-2447`) | hard stale. session handle의 descriptor ref를 원자적으로 새 generation으로 교체하거나 driver 계약 유지 |
| `ER_QPROC_RESULT_CACHE_INVALID` | result-cache 사용을 끄고 plan을 reprepare/reexecute(`db_vdb.c:2297-2319`) | result cache epoch와 plan/descriptor generation을 분리할지 결정 필요 |
| `ER_HEAP_UNKNOWN_OBJECT` | pooled CAS에서 reprepare 신호(`cas_execute.c:1248-1251`) | dependency 누락/DDL race의 fallback; 정상 invalidation primary mechanism으로 쓰면 안 됨 |
| `ER_SM_INVALID_METHOD_ENV`(-294), `ER_SP_EXECUTE_ERROR`(-889) | method/SP runtime error 전달 규약. -294는 callback/invoke 경계에서 pass-through, 그 외는 -889 wrap(`network_callback_sr.cpp:38-55`, `network_interface_cl.c:11614-11625`, `network_interface_sr.cpp:11310-11320`, `query/fetch.c:4236-4249`) | invalidation/reprepare 신호가 아니다. retry whitelist에 넣으면 side effect가 이중 실행될 수 있음 |

`db_vdb.c:2184-2193`도 retry를 세 cache-stale error로만 제한하며 interrupt/timeout/runtime error를 재실행하지 않는 이유를 명시한다. 새 shared-object 계층은 이 whitelist를 넓히지 않아야 한다.

## 4. 새 3계층에 필요한 최소 contract

1. **Identity**: `database + DB user + normalized SQL + compile-affecting session parameters + shape flags + bind-plan variant`를 명시한다. SHA collision 시 canonical bytes 확인 여부도 결정한다.
2. **Dependency set**: immutable descriptor/native plan에 class/serial/synonym/auth 등 dependency OID와 요구 lock을 둔다. metadata만 쓰는 descriptor도 동일 dependency generation을 확인한다.
3. **Generation**: session handle은 raw pointer가 아니라 `{descriptor key, generation}`을 잡는다. schema/auth hard invalidation은 generation을 바꾸고 old handle lookup을 실패시킨다. statistics/bind soft replan에서 generation 유지 여부는 별도 정책이다.
4. **Pin and retire**: handle 장기 ref와 execution pin을 구분한다. invalidation은 publish/remove를 먼저 하고 실제 free는 마지막 execution pin 뒤에 한다. session handle ref가 old descriptor를 무기한 붙들지 않도록 refresh/expiry 규칙이 필요하다.
5. **Lock linearization**: 관련 schema locks를 취득한 뒤 generation/deleted 상태를 다시 확인한다. lock acquisition 전 stale 확인만으로는 현재 `xcache_find_xasl_id_for_execute:1047-1090`보다 약해진다.
6. **Compile single-flight**: miss/hard stale/soft replan마다 누가 compile하는지, waiter는 old generation을 쓸지 block할지 정한다. 실패 시 old entry 복원 또는 error fan-out도 필요하다.
7. **Result cache epoch**: plan replacement에 결과 cache를 승계할 수 있는 조건을 semantic identity로 제한한다. schema/auth invalidation과 statistics-only replan을 구별한다.
8. **Retry class**: hard stale/soft replan/result-cache stale만 retry 가능. runtime/SP/interrupt/timeout은 원 오류를 보존한다.

## 5. 서로 독립적인 열린 정책 질문

- **D-I1 linearization**: execute가 관련 schema lock+generation 재검사를 통과한 시점을 old plan 실행 허용 경계로 둘지, DDL intent가 publish되는 즉시 새 실행을 막을지?
- **D-I2 invalidation timing**: current force-time + transaction-cleanup 이중 producer를 유지할지, transactional invalidation journal로 commit/rollback publish를 통합할지? 자기 transaction의 미커밋 DDL 가시성은 어떻게 보장할지?
- **D-I3 descriptor coupling**: descriptor와 native plan을 하나의 generation으로 함께 폐기할지, metadata descriptor는 유지하고 plan generation만 교체할지?
- **D-I4 compile race**: stale 시 single-flight compiler 동안 waiter가 old generation을 계속 실행, block, 또는 error/retry 중 무엇을 할지? hard schema/auth와 soft stats replan에 서로 다른 정책을 둘지?
- **D-I5 statistics**: UPDATE STATISTICS를 즉시 replan, next-use soft replan, threshold-only 중 무엇으로 볼지? result cache 승계 조건은 무엇인지?
- **D-I6 bind variants**: session별 하나의 chosen plan을 유지할지, histogram bucket별 shared immutable plan variants를 둘지? variant 수/eviction/statistics epoch는?
- **D-I7 stale handle API**: server 내부에서 투명 refresh할지, 기존 `CAS_ER_STMT_POOLING` driver reprepare 계약을 유지할지, 두 방식을 오류 종류별로 나눌지?
- **D-I8 dependency completeness**: class/serial/synonym 외 auth, method/SP signature, collation/timezone parameter 등 dependency producer를 어떤 registry로 전수화할지?

## 6. 확인 공백

- 모든 DDL/GRANT/REVOKE/owner/method-signature producer가 modified-class registry 또는 OID invalidation에 들어오는지 전수 증명하지 않았다.
- execute가 취득하는 related-object lock mode와 각 DDL의 schema lock mode/보유 종료를 종류별로 매핑하지 않았다. 따라서 “이미 시작한 old plan은 항상 완료” 또는 반대를 결론낼 수 없다.
- UPDATE STATISTICS가 현 branch에서 xcache hard invalidation을 직접 유발하는 전체 call chain은 끝까지 증명하지 않았다. RT threshold와 explicit stats update를 분리해 검증해야 한다.
- `time_stored` 상속 replan은 cached client ID 호환을 위한 기존 특례다. 새 descriptor generation에 그대로 복사할지는 정책 대상이다.
