# 바인드 선택도별 계획 변형 감사

- 대상: frozen engine `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`
- 질문: 현행이 한 SQL key에 여러 bind plan을 보관하는지, 새 shared immutable plan 구조가 variant map을 필요로 하는지.
- 방법: 현재 코드만 읽었다. 실행·측정·정책 결정은 하지 않았다.

## 1. 결론부터: 현행은 “한 SQL key = 한 현재 plan”

현 xcache key의 SHA 입력은 정규화 SQL, user, plan 영향 system parameters, host-var **개수**다. bind 값, histogram bucket/selectivity fingerprint는 SHA에 들어가지 않는다.

- key 생성: `CUSTOM_PRINT_4_SHA_COMPUTE`는 user/host-var count를 포함(`src/query/execute_statement.c:113`), SELECT prepare가 alias를 인쇄하고 SHA1을 계산한다(`:15292-15308`). `parser_print_tree`는 system parameters, user OID, host-var count를 붙인다(`src/parser/parse_tree_cl.c:3068-3120,3164-3176`).
- xcache lookup/insert는 SHA1 하나로 한다(`src/query/xasl_cache.c:872-955,1465-1495`). 별도 bind fingerprint/variant key가 없다.
- bind replan은 `statement->flag.recompile=1`로 같은 SHA entry를 교체한다(`src/compat/db_vdb.c:3507-3569`; `xcache_insert :1558-1757`). old entry와 new entry가 transition 동안 공존할 수 있지만 이는 active fixer 회수용 generation overlap이지 재사용 가능한 variant set이 아니다.

따라서 현행은 bind bucket별 plan을 동시에 찾아 쓰지 않는다. 새 variant map은 기존 동작 보존에 필수가 아니라, 서로 다른 세션/bucket의 plan을 병존시키는 새 최적화와 메모리 정책이다.

## 2. fingerprint가 표현하는 것

- 지원 statement는 query/UPDATE/DELETE이고 fingerprint는 각 PT node의 `bind_fp` 슬롯에 저장된다(`db_stmt_bind_fp_ptr`, `db_vdb.c:159-184`; 필드 `src/parser/parse_tree.h:2181-2182,2941-2943,3039-3040`). 즉 process cache가 아니라 session의 retained parse tree 상태다.
- tree walker는 histogram으로 실제 price 가능한 `(column op ?)`와 RANGE만 취급한다(`src/optimizer/histogram/histogram_cl.cpp:2730-2812,2820-2844`). histogram estimate가 없으면 아무 성분도 넣지 않으며 raw value hash를 쓰지 않는다(`:2780-2790`).
- equality는 estimate를 `sel×1e12`로 stepwise 표현하고, range는 0.01 selectivity band로 양자화해 predicate당 대략 100 band 상한을 의도한다(`:2793-2809`). fingerprint는 operator, resolved column name/spec id, band를 order-sensitive mix한다(`:2451-2470,2625-2673`). 여러 predicate의 조합 수에는 코드상 전역 cap이 없다.
- `histogram_bind_fingerprint`는 price 가능한 항이 하나도 없으면 false, 있으면 0 sentinel을 피해 64-bit fingerprint를 반환한다(`:2847-2870`). 이것은 cache identity hash가 아니라 “현재 session plan이 선택된 selectivity territory” 비교값이다.

충돌은 성능 문제다. 서로 다른 selectivity 조합이 같은 64-bit fingerprint면 잘못된 결과가 아니라 덜 적합한 plan을 재사용한다. 반대로 metadata/schema/user key 충돌은 정확성 문제가 될 수 있어 같은 취급을 하면 안 된다.

## 3. first bind와 이후 bind의 현행 제어

### 첫 실행은 parameter와 무관하게 실제 값으로 한 번 고정

- unbound host-variable predicate로 생성된 XASL은 `HV_PRED_PLAN_UNPEEKED`를 가진다(`src/parser/xasl_generation.c:18352,22285,23224`). cache hit/miss 모두 이 flag를 PT statement에 기록한다(`execute_statement.c:15335-15363,15366-15384`).
- execute 시 `hv_pred_plan_unpeeked`이면 `plan_cache_bind_sensitivity`가 꺼져 있어도 fingerprint를 계산하고 값이 다르면 kept post-transform tree에서 plan+XASL만 재생성한다(`db_vdb.c:2240-2283`). SQL-level PREPARE도 첫 실제 bind에서 같은 고정을 수행한다(`:3771-3797`).
- parameter가 off면 이 첫 값 plan이 이후 모든 값에 고정된다. parameter/hint가 on일 때만 이후 fingerprint 변화도 replan한다(`db_is_bind_sensitive :121-157`; kept-tree path `:3615-3648`).

### 기본값과 hint

- `plan_cache_bind_sensitivity`는 client/user-change boolean, 기본 `false`다(`src/base/system_parameter.c:5552-5563`).
- `BIND_SENSITIVE` hint가 statement별 opt-in이며 global parameter보다 우선 true다. `NO_BIND_SENSITIVE`는 없다(`db_vdb.c:121-156`; hint bit `parse_tree.h:1254-1256`).
- 현 코드에는 bind variant 개수, per-SQL variant memory, fingerprint eviction을 제어하는 parameter가 없다.

### generic plan은 안정적인 fallback entry가 아니다

unbound plan은 first-execution marker를 전달하는 초기 plan이다. 실제 bind가 histogram-priceable하면 forced replan이 같은 xcache key를 교체한다. xcache는 recompile 동안 이미 fix한 old plan 실행은 허용하지만 새 lookup용 generic+specialized 두 entry를 유지하지 않는다(`xasl_cache.c:1558-1570,1617-1676`). 따라서 “variant cache miss면 generic plan 사용”은 새 계약이다.

## 4. 다세션 공유에서 나타나는 현행 의미

동일 DB user/SQL의 세션 A와 B가 다른 fingerprint로 replan하면 둘 다 같은 SHA entry를 갱신한다. xcache replacement는 old `time_stored`를 새 plan에 상속해 기존 client XASL_ID가 새 plan도 찾도록 한다(`xasl_cache.c:1739-1745`). 따라서:

1. A가 bucket a plan을 만들고 B가 bucket b plan으로 교체하면 현재 cache에는 b plan 하나가 남는다.
2. A의 PT tree에는 여전히 fingerprint a가 기록되어 있다. A가 같은 a 값을 다시 실행하면 local fingerprint가 바뀌지 않았으므로 replan하지 않고, SHA/time으로 현재 b plan을 얻을 수 있다.
3. 결과 정확성은 동일 SQL 의미로 보존되지만 bind sensitivity의 plan-quality 의도는 세션 간에 약해질 수 있다. 반대로 A가 다른 bucket으로 움직이면 자기 기록값과 비교해 다시 global replacement한다.

이는 코드에서 도출한 동시세션 상호작용이며 실행 측정은 없다. “variant가 반드시 필요”하다는 결론이 아니라, single-current-plan 정책을 유지할 경우 허용하는 성능 의미다.

## 5. retained tree와 비용 경계

- SQL-level PREPARE는 statement name마다 compiled subsession 하나를 `kept_trees`에 보관한다(`src/compat/db_session.h:40-48`; registry `db_vdb.c:193-365`). 동일 name 아래 fingerprint별 tree를 여러 개 보관하지 않는다.
- kept execution은 현재 bind fingerprint가 저장값과 다를 때 같은 tree를 in-place replan하고 저장 fingerprint를 덮는다(`db_vdb.c:3587-3654`). stale cache error면 kept tree를 버리고 stored SQL에서 full compile한다(`:2160-2207`).
- CCI/JDBC prepared handle도 자기 PT statement에 fingerprint 하나와 XASL_ID 하나를 둔다(`:2248-2281`).

따라서 새 bounded variant map이 추가하는 retained memory는 최소 `{fingerprint/key, immutable native plan, dependency/statistics generation, recency/frequency metadata}` × retained variants다. 이미 합의한 per-execution state는 variant와 공유하면 안 된다. post-transform logical tree를 variant마다 복제할 필요는 없고, descriptor당 하나를 유지해 miss 때 새 native plan을 만들 수 있는지는 별도 compiler-artifact 설계다.

## 6. 기존 cap/eviction에서 재사용 가능한 것과 없는 것

- xcache `max_plan_cache_entries` 기본 1000, `max_plan_cache_clones` 기본 1000이다(`src/base/system_parameter.c:2260-2283`). cache hard memory = entries×128KB, soft limit=80%, large clone retention limit은 남는 20%/`UNPACK_SCALE`로 계산한다(`xasl_cache.c:305-336`). 이는 현재 **SQL entry와 full clones**의 전역 cap이지 per-SQL variants cap이 아니다.
- memory/timeout cleanup은 unfixed/unmarked entry 중 old `time_last_used`를 골라 제거한다(`xasl_cache.c:1430-1448,2390-2645`). 한 SQL 아래 variant를 독립 entry로 만들면 기존 LRU를 쓸 수 있지만 hot SQL의 많은 variants가 다른 SQL entries를 밀어낼 수 있다.
- variant를 한 descriptor 내부 child map으로 두면 기존 xcache entry count와 cleanup iterator에 보이지 않는다. child bytes를 `mem_size`에 넣고 per-descriptor cap/child eviction을 새로 만들어야 한다.
- active/fixed entry는 cleanup 대상이 아니다(`:2506-2516`). idle open statement가 heavy plan을 eviction/refetch 허용한다는 Q5 결정과 맞추려면 session handle이 plan child를 영구 pin하지 않고 `{descriptor, desired fingerprint/generation}`로 재조회할 수 있어야 한다.

## 7. YCSB PK shape에서 확정 가능한 범위

현재 YCSB JDBC READ는 `SELECT * FROM <table> WHERE YCSB_KEY = ?`이고 thread별 cached PreparedStatement로 유지된다(`~/dev/cubrid-perftools-internal/ycsb/ycsb/jdbc/.../JdbcDBClient.java:254-266,317-344`; thread별 DB 생성 `core/.../Client.java:838-865`). 이 형태는 fingerprint walker가 인식하는 equality candidate 모양이다.

그러나 실제 histogram 존재, PK equality의 selectivity band가 key마다 같은지, optimizer가 서로 다른 plan을 택하는지는 데이터/통계에 달렸으므로 코드만으로 “variant 불필요”를 증명할 수 없다. YCSB에서 기록할 최소값은 SQL별 distinct fingerprint 수, replan/replace 횟수, fingerprint별 chosen plan identity, hit frequency다. 결과 correctness와 throughput/p99를 함께 보되 variant 필요성 판정은 plan diversity와 replacement churn으로 설명한다.

## 8. 독립 정책 선택지

| 선택 | 기존 동작과 차이 | 메모리/제어 | 정확성 대 성능 |
|---|---|---|---|
| **B1 single current plan 유지** | 현행과 가장 가까움. 첫 bind 또는 later bucket이 global current plan 교체 | variant 추가 메모리 0; compile single-flight/old-valid 정책만 필요 | 정확성 유지. 다세션 plan-quality 간섭/교체 churn 허용 |
| **B2 bounded shared variants** | fingerprint/statistics generation별 plan을 N개까지 병존 | per-descriptor cap, bytes cap, child LRU/LFU, compile dedup 필요 | 성능 최적화. cap 초과 시 fallback/eviction 정책 필요 |
| **B3 generic + bounded specialized** | generic immutable fallback 1개를 유지하고 hot fingerprint만 specialize | B2보다 최소 1 plan 추가; generic 생성/갱신 계약 필요 | miss/compile 중 wait 없이 fallback 가능. generic quality와 memory tradeoff |
| **B4 session-selected single variant** | descriptor metadata는 공유하지만 chosen native plan은 session별 하나 | plan memory가 다시 sessions에 비례 | 세션 간 간섭 제거, 공유 메모리 목표 약화 |

이 선택들은 query correctness가 아니라 plan quality, compile churn, memory bound의 정책이다. schema/auth generation 일치는 정확성 조건이다. statistics generation은 선택도·재최적화 결과의 일관성을 위한 별도 축이며, 통계만 바뀐 기존 유효 계획은 Q4 결정에 따라 사용할 수 있다.

결정 전 서로 독립적으로 답할 질문:

1. single-current-plan의 세션 간 plan-quality 간섭을 허용할 것인가?
2. variant를 둔다면 cap을 count, bytes, 또는 둘 다로 둘 것인가? 전역 cap과 per-SQL cap의 관계는?
3. eviction miss에서 compile을 기다릴지, generic/current valid plan을 즉시 쓸지?
4. generic plan을 stable fallback으로 별도 유지할지?
5. fingerprint collision/estimate band를 단지 성능 힌트로 취급하고 plan correctness identity에서는 제외할지?

## 9. 확인 공백

- YCSB의 실제 distinct fingerprint와 chosen plan diversity는 측정하지 않았다.
- `histogram_bind_fingerprint`가 지원하는 모든 predicate 조합을 전수 검증하지 않았다.
- global parameter가 session별로 달라질 때 shared descriptor lookup/behavior key에 포함되는지는 새 구조 정책 대상이다. 현 SHA에는 bind-sensitivity enable bit가 직접 들어가지 않는다.
- current same-SHA recompile의 다세션 plan-quality 간섭은 코드상 경로에서 도출했으나 concurrency test로 재현하지 않았다.
