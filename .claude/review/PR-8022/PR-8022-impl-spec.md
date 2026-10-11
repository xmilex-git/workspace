# PR #8022 리뷰 후속 구현 스펙 (초안 — 범위 확정 전)

기준: dpin HEAD `23a5e5561`(develop merge-base `15e7dc8b5`). 리뷰: `PR-8022-report.md`(2026-10-04). 측정 원자료: `.git_ignored_dir/scratch/pr8022-review/{perf,build,sizes}/`.
원칙: 답은 바뀌지 않는다(P0). 항목마다 독립 커밋, 커밋마다 게이트(optdebug·release 빌드 + CTP sql 전수 + medium). 게이트를 통과하지 못한 커밋 위에 쌓지 않는다. 용어는 `CONTEXT.md` 용어집.

## A. 반영 후보 (우선순위 순)

### A1. `XASL_STATE` 의 도메인 상태를 작은 헤더로 절연 (빌드 fan-out)
- 현상: `query_executor.h` 가 `domain_plan.h`(→ `domain_rules.h` → `object_domain_convert.h`)를 포함하는 이유는 `XASL_STATE` 에 값으로 든 `RESOLVED_DOMAIN_TABLE`·`DOMAIN_EXECUTION_STATE` 둘뿐이고, 두 구조체의 멤버는 전부 포인터·정수·bool 이다(`domain_plan.h:448~502`). 측정(`ninja -t deps`): `domain_plan.h` 203 TU, `domain_rules.h` 212 TU, `object_domain_convert.h` 218 TU 가 재컴파일 의존 — 실제로 도메인 계획 항목을 읽는 TU 는 10여 개.
- 변경: 새 헤더 `src/query/domain_state.h` 에 전방 선언(`struct DOMAIN_PLAN; struct RESOLVED_DOMAIN; struct DOMAIN_COMPARE; struct DOMAIN_ELEMENTS; struct RESOLVED_INDEX_KEYS; struct DOMAIN_EXECUTION_TEMPORARY; struct tp_domain; struct db_value;` 등)과 `RESOLVED_DOMAIN_TABLE`·`DOMAIN_EXECUTION_STATE` 정의만 둔다. `domain_plan.h` 는 그 헤더를 포함하고 두 구조체 정의를 뺀다. `query_executor.h` 는 `domain_plan.h` 대신 `domain_state.h` 를 포함한다. `enum DOMAIN_VALUE_STATE` 는 `value_states` 의 해석이므로 함께 옮긴다.
- 불변식: 구조체 레이아웃·`sizeof(XASL_STATE)`(232) 불변. 서버 전용 가드 유지.
- 수용 기준: 빌드 green; `ninja -t deps` 로 `domain_rules.h` 역의존 TU 수가 212 → `domain_resolve.h` 수준(약 50) 이하; `touch src/query/domain_rules.h && ninja -n | grep -c Building` 으로 재확인.

### A2. 번호 규약 통일: 1-based/0 사용 세 곳을 0-based/-1 로
- 현상: `resolved_index`·`ref`·`compare_index`·`resolved_elements_index`·`resolved_keys_index`·`constant_branch` 는 0-based/-1, `DOMAIN_PLAN_ITEM.node_domain_index`·`DOMAIN_PLAN_ITEM.temporaries[2]`·`aggregate_accumulator_domain.temporary` 는 1-based/0 (`domain_plan.h:76~91`, `xasl_aggregate.hpp:88`). 접근자가 `- 1` 보정(`qexec_node_domain_index`), 상태 가이드에 표가 필요했다.
- 변경: 세 필드를 0-based, 없음 = -1 로. 로드(`domain_plan.c` 번호 매기기, `domain_plan_add_temporaries`), 접근자(`domain_resolve.h`), 읽는 곳(`fetch.c`, `query_aggregate.cpp`, `query_analytic.cpp`, `query_executor.c`, `query_dump.c`)을 모두 바꾼다. 항목 초기화가 memset 0 에 기대던 자리는 명시 -1 초기화로.
- 수용 기준: optdebug 의 `qexec_owns_node_domain`·`qexec_execution_temporary` assert 통과, CTP 전수 동일.

### A3. `DOMAIN_PLAN_ITEM` union 태그 + 가변 판정 불변식 + 이름
- union `compares`/`temporaries[2]` 를 opcode 로만 구분 → `flags` 에 `DOMAIN_PLAN_ITEM_COMPARES`(0x04) 를 두고 읽는 쪽이 플래그로 분기, optdebug 는 opcode 와 일치 assert.
- "가변" 판정 세 벌(`REGU_VARIABLE_VARIABLE_DOMAIN` regu 플래그 — `domain_plan.c:1499` 세팅, `fetch.h:63` 읽기; `DOMAIN_PLAN_VARIABLE` 항목 플래그; `regu_is_variable_pos`): 로드 끝에 `assert (REGU_VARIABLE_IS_FLAGED (regu, REGU_VARIABLE_VARIABLE_DOMAIN) == ((item->flags & DOMAIN_PLAN_VARIABLE) != 0))` 를 두고 `regu_var.hpp` 의 플래그 주석에 그 관계를 적는다.
- `RESOLVED_DOMAIN_TABLE.frozen` → `readable`(뜻: 값·확정을 읽어도 된다; 확정은 그 뒤에도 이어진다). 읽는 곳 전부 치환.
- `qexec_resolve_domains_internal` 머리말의 단계 번호(1, 2, 3(접힘), 4, 5, 6, 7, 7b, 8, end)를 번호 없이 함수 이름 순서로 다시 쓴다.
- `DOMAIN_DEFERRED_ERROR` 의 `arg`/`arg2`(kind 마다 뜻이 다름)를 이름 있는 union 으로.
- `query_dump.c` 의 `slot=` → `resolved=`, `VOLATILE` → `NON_CACHEABLE`.

### A4. 모듈 개요 주석
- `domain_plan.h` 상단에 (1) 자료 흐름(컴파일 → 로드 도출 → 실행 전 도메인 확정 → 행), (2) 번호 공간(`resolved_index`/`ref`/`node_domain_index`/`compare_index`/`temporaries` 가 각각 어느 배열을 가리키나), (3) 소유권(한 블록·owner 스레드·PX 복사), (4) 읽는 순서를 40줄 안으로. `pr8022-domain-state-guide.md` §1~§3·§12 의 요약.

### A5. 실행 종료의 `pr_clear_value` 호출 줄이기 (측정: case-30 13.0k, in-30 2.5k, pkand-30 2.5k 명령/실행)
- 현상: `qexec_clear_resolved_domains` 가 `vals[]` 전부에 `pr_clear_value` 를 부른다. 바인드는 `qexec_share_value` 가 payload 를 공유해 해제할 것이 없다.
- 변경: 값마다 호출 전에 인라인 검사 — `DB_NEED_CLEAR (v) || TP_IS_SET_TYPE (DB_VALUE_DOMAIN_TYPE (v)) || DB_VALUE_DOMAIN_TYPE (v) == DB_TYPE_VOBJ` 일 때만 호출(`pr_clear_value` 가 실제로 해제하는 조건과 같게; `qexec_share_value` 주석 참조). 같은 검사를 `temporaries[]` 값에도.
- 수용 기준: valgrind/ASan 없이도 optdebug CTP 전수에서 누수 경고 0(기존 `er` 로그 비교), case-30 재측정에서 clear 가 13k → 3k 이하.

### A6. 실행당 할당 합치기 (측정: `qexec_alloc_resolved_domains` 370~1,150 명령 + `db_private_alloc/free` 호출 2~4회/실행)
- 현상: 값·확정 블록(1) 외에 `temporaries`·`scope_generations`(각각), ALL/SOME 원소 scratch·출력, 인덱스 스캔 블록, 세션변수 타입, 상수 가지 상태, `comparison_resolved` scratch 가 따로 할당된다(`domain_resolve.c` 의 `db_private_alloc` 14곳). 크기는 전부 로드가 안다.
- 변경(1단계만): `temporaries`·`scope_generations` 를 값·확정 블록 뒤에 붙인다(`qexec_alloc_resolved_domains` 가 n_temporaries·n_scopes 를 받고 `qexec_alloc_execution_temporaries` 는 초기화만). 해제는 블록 하나. PX 복사(`qexec_copy_resolved_domains`)도 같은 경로. 나머지(원소·인덱스·상수 가지 scratch)는 2단계 후보로 남긴다.
- 수용 기준: 실행당 `db_private_alloc` 호출 수가 상관 scope 있는 문장에서 3 → 1; CTP 전수 동일.

### A7. (선택) 같은 키 쌍의 확정 비교 재사용 (측정: in-30 10.3k, pkand-30 10.7k, and-30 12.2k, case-30 11.8k 명령/실행 — 비교 30개 × ~350)
- 변경: `qexec_resolve_domains_internal` 의 비교 단계에서 직전에 확정한 (lhs 키, rhs 키, 상수 변환 없음) 와 같으면 `DOMAIN_COMPARE` 를 복사(72 B)하고 `value[side]` 만 자기 것으로. 상수 쪽 변환이 있는 비교는 제외.
- 위험: 비교마다 다른 `value[]`·`compare_index` — 복사 뒤 덮어쓰는 필드를 빠뜨리면 다른 항의 값을 읽는다. optdebug 에 `domain_compare_equal` 교차 검사.

### A8. (선택, 효과 작음) 정적 계획 빠른 길 — 보류 권고
- 측정: pk-1 1.5k(0.36%), nobind 0.9k(0.89%), sel-1 0.4k. `vals = in` 별칭 + clear 가드 + PX 복사 분기로 얻는 것이 1% 미만이라 복잡도 대비 보류.

### A9. PR 본문 수정 (코드 아님)
- `domain_resolver.c/h` → `domain_rules.c/h`; "GATE 비트를 붙입니다" → "기대 도메인이 없는 자리는 `tp_Variable_domain` 으로 싣고 로드가 `REGU_VARIABLE_VARIABLE_DOMAIN`·`DOMAIN_PLAN_LATE_BIND` 를 도출합니다"; "게이트/슬롯" → 용어집 이름(실행 전 도메인 확정 / 가변 POS).

## B. 반영하지 않는 것 (근거)
- 타입 쌍 비교 표 pool 과대 할당: 오류. `domain_key_pairs_make` 끝에서 `realloc (pool, sizeof (DOMAIN_COMPARE) * n_pool)` 로 줄인다(상주 141 KB + entry 26 KB, 빌드 0.8 ms; gdb 실측 n_keys 57, n_pool 1,956).
- `btree_compare_key` 래퍼 호출 비용: `btree_compare_key_with` 가 `STATIC_INLINE` 이라 없음.
- 날짜·TZ `_core`/래퍼 분리(40개): 래퍼가 core 를 부르는 구조라 중복 없음.
- 도메인 계획 메모리 압축(항목 80 B, `fixed` 56 B 중복): #375 의 몫. 기존 측정 — 공유 pool + 32 B 항목 6.9 %, 단순 바인드 항목 제거 2.4 % (로드 바이트 기준).
- `tp_value_cast_internal` 의 switch + 간접 호출: ADR 0023 에서 측정·수용.
- case-30 의 상수식 평가 51k: 행에서 하던 일을 실행 전으로 옮긴 것(설계).

## C. 게이트
- 커밋마다: optdebug 빌드 → release 빌드(동시 금지) → `just ctp sql PR=8022` 전수(기준 17483/17483) + `just ctp medium PR=8022`(975/975) → 소형 8셀 재측정(`pr8022-review/perf/drive2.sh`, `-camp` 변형, 3회 중앙값; A5·A6·A7 은 해당 셀의 명령 수 감소를 보고). A1 은 `ninja -t deps` 역의존 수.
- CTP 는 컨테이너 `just ctp` 만, 호스트 `ctp.sh` 금지. 실행 워커는 Sonnet.
- 구현 워커(Fable 5.1, effort medium)는 항목 하나 = 커밋 하나, 소스 밖(문서·PR 본문)은 건드리지 않음, `/tmp` 금지, 스크래치는 `.git_ignored_dir/scratch/pr8022-impl/`.
