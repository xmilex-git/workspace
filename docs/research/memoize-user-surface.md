# 11.5 Memoize 사용자 표면 인벤토리

- 티켓: [#146](https://github.com/xmilex-git/workspace/issues/146) (맵 [#144](https://github.com/xmilex-git/workspace/issues/144))
- 근거: JIRA CBRD-26345 + 자손(CBRD-26413, CBRD-26574, CBRD-26681), 엔진 소스 `/home/cubrid/dev/cubrid` (develop, VERSION=11.5.0), 머지된 PR CUBRID/cubrid#6555, #6652, #6682, #6877, #7018
- 원칙: JIRA와 코드가 다르면 **코드 우선** — 본문에 불일치를 명시한다.

## 0. 한 줄 요약

Memoize는 nested-loop 조인의 **내측(inner) 스캔 결과를 조인 키별로 서버 메모리에 캐시**해, 같은 외측 값이 반복될 때 내측 테이블/인덱스 스캔과 조건 평가를 생략하는 11.5 신기능이다(CBRD-26345, PR #6555/#6652). 사용자 표면은 정확히 두 가지다: 시스템 파라미터 `memoize_memory_limit` 하나와 SQL trace의 `MEMOIZE` 블록 하나. **힌트·구문·에러 메시지는 없다.**

## 1. 적용 조건 (언제 켜지는가)

메모이즈 storage는 실행 시점에 서버가 자동 생성한다. 옵티마이저 플랜 선택이 아니라 **실행기(executor)의 런타임 결정**이다.

생성 지점 게이트 — `qexec_execute_mainblock_internal` (`src/query/query_executor.c:16575` 부근):

```c
if (spec_level == 0 && level >= 1 && !mvcc_select_lock_needed)
  new_memoize_storage (thread_p, xptr);
```

- `level >= 1`: XASL `scan_ptr` 체인에서 두 번째 이후의 스캔, 즉 **nested-loop 조인의 내측 테이블에만** 적용된다. 최외곽(driving) 테이블에는 적용되지 않는다. hash join(`query_hash_join.c`)이나 merge join 경로에는 memoize 코드가 전혀 없다 — NLJ 전용.
- `spec_level == 0`: 일반 `spec_list`에만 (merge spec 제외).
- `!mvcc_select_lock_needed`: 행 잠금이 필요한 스캔(UPDATE/DELETE의 대상 검색, SELECT FOR UPDATE 등)에서는 비활성 — CBRD-26413 회귀(파티션 혼합 multi-update에서 `locator_attribute_info_force` assert로 서버 abort) 수정으로 추가된 게이트다(PR #6682, 1줄 수정).
- 병렬 스캔(parallel query)과 결합 시 **워커별로 각자 storage를 생성**하고(`src/query/parallel/px_scan/px_scan_task.cpp:364`) 종료 시 통계만 병합한다(`src/xasl/xasl_iteration.cpp:187-201`).
- 파티션 테이블은 파티션 전환 시 storage를 비우고 재생성한다(`src/query/query_executor.c:8111-8115`).

이후 `new_memoize_storage` → `memoize::storage::new_storage` (`src/query/memoize.cpp:692-735`)가 XASL 형태 검사(`possible_check`, `memoize.cpp:39-160`)를 통과해야 실제 생성된다. 아래 §2가 그 검사 목록이다.

캐시 키는 내측 스캔의 술어(where_key/where_pred/where_range/if_pred/after_join_pred와 dptr 하위질의)에 등장하는 **외측 상관 값(TYPE_CONSTANT regu var)** 들이다(`key_maker`, `memoize.cpp:162-599`). 즉 "조인 키가 같으면 내측 결과도 같다"는 가정 하에, 키가 같은 외측 행이 오면 캐시된 내측 행 목록을 그대로 재생한다. hit 시 실제 스캔·조건 평가를 생략하고, miss 시 실제 스캔을 수행하며 결과 행을 put하고 스캔 끝에 종료 마커를 put한다(`qexec_execute_scan`/`qexec_execute_nljoin_with_memoize`, `query_executor.c:8321-8530`).

## 2. 비적용 조건 (언제 안 켜지는가)

`possible_check` (`src/query/memoize.cpp:39-160`) + `new_storage`에서 다음이면 memoize 없이 일반 스캔으로 실행된다:

1. **파라미터 0**: `memoize_memory_limit = 0`이면 storage를 만들지 않는다(`memoize.cpp:1046-1051`). 유일한 끄는 방법.
2. **조인 키 없음**: 술어에서 외측 상관 값을 하나도 못 찾으면(`key_cnt == 0`) 생성 안 함(`memoize.cpp:720-723`) — cartesian product 등 조인 조건 없는 경우.
3. **대상 접근 방식 제한**: `TARGET_CLASS`(heap/index scan)와 `TARGET_LIST`(list scan)만 허용. `TARGET_CLASS_ATTR`, `TARGET_SET`, `TARGET_JSON_TABLE`, `TARGET_METHOD`, `TARGET_REGUVAL_LIST`, `TARGET_SHOWSTMT`, `TARGET_DBLINK`는 제외(`memoize.cpp:78-86`). 접근 메서드도 sequential/index만 — record-info/page-scan/key-info/node-info/schema/json_table 스캔 제외(`memoize.cpp:99-106`).
4. **시스템 클래스·MVCC 비활성 클래스**(root class, `db_serial`, `db_partition` 등) 제외(`memoize.cpp:68`).
5. **집합 타입**: 내측 val_list에 `SET`/`MULTISET`/`SEQUENCE` 타입 컬럼이 있으면 제외(`memoize.cpp:117-120`).
6. **복수 spec / bptr·fptr**: spec이 둘 이상이거나 해당 노드에 bptr_list/fptr_list(선행 상관 하위질의/obj fetch)가 붙으면 제외(`memoize.cpp:53-61`).
7. **상관 하위질의(dptr)**: `XASL_LINK_TO_REGU_VARIABLE`이 아닌 dptr이 있거나, dptr/aptr가 재귀적으로 memoize 가능 조건을 통과하지 못하면 제외(`memoize.cpp:127-156`).
8. **행 잠금 필요 스캔**: §1의 `!mvcc_select_lock_needed` 게이트(CBRD-26413).

**JIRA와의 불일치(코드 우선)**: CBRD-26345 본문의 제약 "5. update statistics 미실행 시(NDV 통계 없음) 비적용", "6. 조인 컬럼 중복률 곱이 0.5를 넘지 않으면 비적용"은 **최종 코드에 없다**. PR #6652가 NDV 기반 사전 차단을 제거하고 런타임 게이트(1,000회 시도 후 hit율 50% 미만이면 차단)로 대체했다 — 커밋 메시지에 명시("Instead of blocking memoize based on NDV, execute 1,000 attempts and block memoize if the hit ratio falls below 50%", `e1c7fcf21`). 따라서 통계 유무는 memoize 적용 여부와 무관하다.

## 3. `memoize_memory_limit` 파라미터

정의: `src/base/system_parameter.c:5352-5363` (`PRM_NAME_MEMOIZE_MEMORY_LIMIT`, `system_parameter.c:801`)

| 항목 | 값 | 근거 |
|---|---|---|
| 타입 | BIGINT, SIZE 단위(`PRM_SIZE_UNIT` — `2m`, `4096k` 등 표기 가능) | `system_parameter.c:5354-5355` |
| 기본값 | 2MB (`2 * 1024 * 1024`) | `system_parameter.c:5357` |
| 하한 | **0** (0 = 기능 비활성) | `system_parameter.c:5360` + `memoize.cpp:1048` |
| 상한 | 없음 | `system_parameter.c:5359` (NULL_SYSPRM_PARAM_VALUE) |
| 플래그 | `USER_CHANGE \| FOR_CLIENT \| FOR_SERVER \| FOR_SESSION \| FOR_QRY_STRING` | `system_parameter.c:5354` |

- `FOR_SESSION`+`USER_CHANGE`: `SET SYSTEM PARAMETERS 'memoize_memory_limit=0'`으로 세션 단위 변경 가능. cubrid.conf에도 설정 가능(FOR_SERVER/FOR_CLIENT).
- `FOR_QRY_STRING`: 파라미터 값이 플랜 캐시 키에 포함되므로, 값을 바꾸면 별도 플랜 캐시 엔트리를 쓴다(같은 SQL이라도 재컴파일).
- **불일치(코드 우선)**: 티켓/JIRA에 "하한 2MB"로 알려져 있었으나 코드상 하한은 0이다. 0은 "끄기"이고, 0 초과의 아주 작은 값(예: 1KB)도 설정 자체는 허용된다(즉시 FULL로 자기-비활성화될 뿐). JIRA 본문의 파라미터명 `memoize_hash_size`도 구현 과정에서 `memoize_memory_limit`으로 바뀐 옛 이름이다.
- 이 한도는 **storage 인스턴스 1개당** 한도다. 병렬 워커별·XASL 노드별로 각각 storage를 가지므로, 다중 조인 + 병렬 실행에서는 쿼리 전체 사용량이 `한도 × (memoize되는 노드 수 × 워커 수)`까지 갈 수 있다(`px_scan_task.cpp:364`).

### 한도 초과 시 동작

`storage::get()/put()/put_nullptr()`가 매 호출마다 현재 크기를 검사한다(`memoize.cpp:820-824, 902-906, 948-952`):

- 현재 크기(`get_current_size()` = 키 + 값 + 해시 엔트리 + 버킷 배열 + struct 자체, `memoize.cpp:1035-1038`)가 한도 이상이면 `disabled = true`, `FULL` 반환.
- `FULL`을 받은 호출부는 **즉시 `clear_memoize_storage`로 캐시를 통째로 해제**하고(`memoize.cpp:1099-1107, 1151-1159, 1199-1207`) 이후 일반 스캔으로 계속 실행한다. 쿼리는 실패하지 않고, 에러/경고도 없다.
- 같은 경로로 **런타임 hit율 게이트**도 동작한다: hit+miss가 1,000회(`MEMOIZE_FREE_ITERATION_LIMIT`, `memoize.hpp:32`)를 넘긴 시점에 hit율이 50%(`MEMOIZE_HIT_RATIO_THRESHOLD`, `memoize.hpp:33`) 미만이면 FULL과 동일하게 비활성+즉시 해제(`memoize.cpp:907-914`).
- "비활성 후에도 조회 오버헤드가 남는" 문제는 CBRD-26574(PR #6877)에서 즉시 해제로 수정됐다. 그 부작용으로 **비활성화된 memoize는 trace에 아예 남지 않는다**(storage가 해제되므로).

## 4. SQL trace의 MEMOIZE 블록

출력 위치: text trace `src/query/query_dump.c:3875-3882`, JSON trace `query_dump.c:3298-3307`. 형식:

```
MEMOIZE (time: 12, hit: 2999995, miss: 5, size: 1KB, enabled: true)
```

| 필드 | 의미 | 근거 |
|---|---|---|
| `time` | memoize get/put 연산에 쓴 누적 시간, **밀리초**(`TO_MSEC`). trace가 켜진 경우에만 측정 | `query_dump.c:3878`, `memoize.cpp:1076-1079, 790-802` |
| `hit` | 조인 키 조회 성공 횟수(캐시된 행 재생 또는 "결과 없음" 마커 적중 포함) | `memoize.cpp:857-861` |
| `miss` | 조인 키 조회 실패 횟수(실제 스캔으로 폴백한 키 수) | `memoize.cpp:843` |
| `size` | 현재 캐시 메모리 사용량 KB (`get_current_size()/1024`: 키+값+해시 오버헤드 포함) | `query_dump.c:3880`, `memoize.cpp:1035-1038` |
| `enabled` | `true`=끝까지 활성. `false`=비활성 플래그가 선 상태 | `query_dump.c:3881` |

주의점:

- **`hit > 0`일 때만 출력된다** — CBRD-26681(PR #7018)에서 "memoize가 실제 기여하지 않았는데 MEMOIZE 항목이 찍히는" 문제를 수정(`query_dump.c:3875`, `3298`). 따라서 trace에 MEMOIZE가 없다고 해서 memoize 시도가 없었다는 뜻은 아니다(적용 불가였거나, hit 0이었거나, 한도/hit율 초과로 해제된 경우 모두 미출력).
- CBRD-26574 이후 비활성화는 즉시 해제를 동반하므로, 단일(비병렬) 실행에서 `enabled: false`를 보기는 사실상 어렵다. 병렬 실행에서는 워커별 storage의 통계·disabled 플래그를 병합해 출력하므로(`xasl_iteration.cpp:187-201`) `enabled: false`가 나타날 수 있다(어느 워커든 비활성이면 false, hit/miss/size는 워커 합산).
- hit/miss는 **행 수가 아니라 키 조회 수** 기준이다. CBRD-26345의 예시(300만 행, 키 5종): `hit: 2999995, miss: 5`.
- 중첩 NLJ에서는 내측 레벨마다 MEMOIZE 블록이 따로(들여쓰기로 중첩되어) 출력된다 — CBRD-26574 본문의 5-테이블 조인 trace 참조.

## 5. 끄는 방법 — 힌트 없음 확인

- **힌트는 존재하지 않는다.** `src/parser/` 전체에 memoize 관련 토큰·힌트가 없다(`grep -ri memoize src/parser` 0건). `NO_MEMOIZE` 같은 힌트도 없다.
- 유일한 제어 수단은 파라미터: `SET SYSTEM PARAMETERS 'memoize_memory_limit=0'`(세션) 또는 cubrid.conf에 `memoize_memory_limit=0`(전역). 0이면 `new_memoize_storage`가 storage를 만들지 않는다(`memoize.cpp:1046-1051`).
- 그 외 간접 수단은 없다(옵티마이저 레벨/플랜과 무관, `CREATE`/`ALTER` 옵션 없음).

## 6. 성능 고려사항·함정

1. **효과 조건**: 외측 조인 키의 중복이 많을수록(NDV가 작을수록) 이득. CBRD-26345 벤치: 300만 행 × 5키 조인에서 6.44초 → 2.30초, ioread 32,973 → 7,399.
2. **자기 방어 장치**: 키 중복이 적으면 1,000회 시도 후 hit율 50% 미만에서 자동 비활성+해제되므로 최악 오버헤드는 초기 1,000회의 put 비용 + 캐시 조회 비용으로 제한된다(CBRD-26574 이후). 26574 이전에는 비활성 후에도 오버헤드가 남았다(11.5 최종 코드에는 해당 없음).
3. **메모리**: 한도는 storage당이며 노드 수 × 병렬 워커 수만큼 곱해질 수 있다(§3). 기본 2MB라 보통 무해하지만, 한도를 크게 올린 세션에서 다중 조인+병렬이면 서버 프라이빗 힙 사용량에 유의.
4. **캐시 정확성 전제**: 같은 트랜잭션·같은 스캔 내 재사용이므로 일반 SELECT에선 안전. 행 잠금이 필요한 경로는 CBRD-26413 이후 원천 차단(잠금을 건너뛴 캐시 행 재사용이 abort를 유발했던 회귀).
5. **관찰 함정**: trace의 `time`은 trace on일 때만 측정되고, MEMOIZE 블록은 hit>0일 때만 보인다 — "안 보임 = 미적용"이 아니다(§4).
6. **플랜 캐시**: `FOR_QRY_STRING`이라 파라미터 값을 바꾸면 플랜 캐시 엔트리가 분리된다. A/B 비교 시 recompile 없이도 값 변경만으로 별도 엔트리를 탄다.
7. **매뉴얼 공백**: 엔진 `conf/` 샘플과 cubrid-manual(en/ko)에 `memoize` 언급이 전혀 없다(2026-08-26 기준 grep 0건) — 본 맵(#144)의 문서화 대상.

## 7. JIRA 추적 계보

| 티켓 | 내용 | PR |
|---|---|---|
| CBRD-26345 | memoize 구현(본체). 제약·파라미터 초안 | #6555(초기), #6652(NDV 게이트 제거→런타임 hit율 게이트, malloc 할당, 해제 시점 변경) |
| CBRD-26413 | 회귀: multi-update(파티션 혼합)에서 서버 abort → `mvcc_select_lock_needed`면 memoize 금지 | #6682 |
| CBRD-26574 | 비활성화 후 잔여 오버헤드 제거 — 비활성 조건에서 즉시 storage 해제, 비활성 시 trace 미출력 | #6877 |
| CBRD-26681 | 미사용(hit==0) 시 trace의 MEMOIZE 항목 미출력(JSON/text 공통) | #7018 |
