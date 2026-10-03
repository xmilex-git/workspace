---
status: accepted
date: 2026-10-03 (2026-09-29 판 #374 을 최종 구현 기준으로 다시 씀)
basis: CUBRID/cubrid#8022 HEAD 23a5e5561 (develop 15e7dc8b5 동기화)
locked-by: xmilex-git/workspace#352 D-352-01~03 (2026-09-25) · #354 D-354-03~05 (2026-09-26) · #371 D1·D3 (2026-09-28) · #374 D-374-23·30 (2026-09-29, 커밋 14a3f97f4)
---
# 모든 비교 확정은 타입 쌍 비교 표의 칸이다 — 두 쪽 키를 행 전에 아는 자리는 칸을 자기 확정 비교에 복사하고, 컬렉션 원소·인덱스 키는 표의 행을 보기로 쓴다

비교 확정의 계산은 한 함수 `domain_resolve_comparison` 이고, 그 입력은 두 쪽의 비교 키(`DOMAIN_COMPARE_KEY`: 타입·codeset·collation)뿐이다. 결과 `DOMAIN_COMPARE` 는 develop 비교의 내용 — 비교 방법(`DOMAIN_COMPARE_DIRECT`/`CONVERT`/`COLLATIONS`/`OBJECT`/`RANK`/`VALUES`/`KEYS`), 어느 쪽을 어떤 변환기로 어떤 목표에 먼저 바꾸는지(`first`·`conv[2]`·`target[2]`), 어떤 `cmpval` 과 collation 을 쓰는지, 변환이 실패할 때의 답(`source[2]`·`converted_first`·`failed`·`rank`), DIRECT 면 관계 연산자별 비교 연산자 함수 표(`operator_functions`) — 를 담는다.

- **타입 쌍 비교 표**는 부팅 때 한 번 만든다(`domain_type_pair_table_init`; 비교에 쓰이는 값 타입 30종 × 등록 collation, 값·계획에 무관). 두 쪽 키를 행 전에 아는 자리 — 술어 항, FIELD·NULLIF·LEAST·GREATEST, LIMIT 의 row count, 머지 조인의 열 쌍 — 는 그 칸을 자기 확정 비교에 복사한다: 두 쪽이 고정 도메인이면 로드가(`DOMAIN_COMPARE_PLAN.fixed`), 한쪽이라도 가변이면 실행 전 도메인 확정이(`qexec_resolve_compare` → `resolved_domain.compares[compare_index]`; 계획의 method 는 `LATE_BIND`/`LATE_BIND_SESSION`). 행은 자기 확정 비교만 읽으므로 그 첫 64바이트 배치가 유지된다.
- **키를 데이터만 아는 자리**는 표의 행을 보기로 쓴다. ALL/SOME 의 오른쪽(`DOMAIN_ELEMENT_COMPARE_PLAN.kind`: PAIR = 리스트 열·비컬렉션 하나의 확정 비교, ROW = 행이 만드는 컬렉션 — 항목 키의 표 행, LATE_BIND = 실행 전 확정이 채운 `DOMAIN_ELEMENTS`; 실행의 `read`: NONE/POSITIONS/ROW/PAIR). 인덱스 키는 스캔 open 이 키 계획에서 `BTID_INT.search_keys`(NONE = 계획 밖 B-tree 검색, OWN = 모든 값이 컬럼 자신의 키, OTHER = 다른 키를 받는 컬럼이 있음)를 정하고, B-tree 비교 `domain_search_key_compare` 는 OTHER 일 때만 표 행을 본다. 컬렉션 원소 비교 표와 스캔별 인덱스 키 비교 표는 없다.
- **검색 키 비교기** `BTID_INT.search_compare`(DIRECT = 단일 컬럼 `cmpval` 직접, MIDXKEY_PLAIN = 복합 키를 원소 비교 없이, RESOLVED = 타입·collation 검사 뒤 키 계획의 비교)와 해시 빌드 키 계획은 비교 확정이 아니라 빠른 길·변환기 선택이다.
- **행**: `eval_compare_term` 이 DIRECT 면 현재 연산자의 비교 연산자 함수를 바로 부르고, 그 밖은 `eval_value_rel_cmp` 가 확정의 변환기와 `cmpval` 을 쓴다. 비교 쪽에서 값을 보고 타입을 정하는 코드는 없다(제자리 coerce·힙 전환 삭제).

결정 원문: #352 D-352-01~03·07, #354 D-354-03~05, #371 D1·D3, #374 D-374-23·30.

## Considered Options

- **보관 여섯 갈래**(확정 비교·비교 연산자 함수, 컬렉션 원소 비교 표, 인덱스 키 비교 표, 타입 쌍 비교 표, B-tree 검색 키 비교기, 해시 빌드 키 계획)**는 두고 조회·PX 복사·교차 검사만 한 인터페이스로**: 기각. 구조 수가 그대로라 "새 비교 경로는 어느 것을 쓰나" 가 코드만으로 안 보였다(F-374-06).
- **헤더 주석 표만**: 기각. 같은 이유.
- **비교 도메인을 피연산자 regu 항목이나 `SCAN_ID` 에 두기**: 기각. 비교는 자리(항)의 것이고 같은 regu 가 여러 항에 쓰인다.
- **develop 의 `tp_value_compare_with_error (do_coercion=1)` 를 행에 그대로**: 기각. 행마다 타입 판정과 임시 변환이고(S-09·S-10), 상수 쪽 제자리 coerce 가 클론 공유 상수를 바꿔 앞 실행의 바인드가 뒤 실행에 끌려갔다(`cbrd_24598`).

## Consequences

- 보관 구조는 둘(자리별 복사, 타입 쌍 비교 표)이고 PX 복사는 확정 비교뿐이다(표는 공유, 불변). optdebug 교차 검사도 한 곳이다.
- 컬렉션 원소·B-tree 검색 키의 행 경로는 "구조별 조회" 에서 "표 행 조회" 로 — O(1)이지만 B-tree 경로가 뜨거워 명령 수로 쟀다(2026-09-29): P5-eq·P5-mro 0.7~1.7% 감소, P6-in H=·H!= 2.3% 감소, +0.5% 넘은 칸 없음.
- 상수 쪽 변환 실패는 상수 오류다: 술어 항·ALL/SOME 은 실행 전 -181(오류의 타입 이름 순서는 `source`·`key_range` 로 develop 과 같게), 항 밖 비교(FIELD·LEAST 등)는 develop 의 RANK 답을 유지한다.
- 되돌리는 길: 측정이 기준을 넘으면 인덱스 키 비교 표만 스캔별 보관으로 되돌린다(D-374-23). 쓰지 않았다.
