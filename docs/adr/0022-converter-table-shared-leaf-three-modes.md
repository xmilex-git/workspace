---
status: accepted
date: 2026-09-22
locked-by: xmilex-git/workspace#320 (2026-09-22)
---
# 변환기 표는 `tp_value_cast_internal`·`tp_value_coerce_strict` 와 공유하는 셀 함수(leaf)의 3-모드 정적 표다

계획된 변환기의 원소는 (원 타입, 목표 타입, 변환 모드)가 고정된 **셀 함수(leaf)** 이고, 변환 모드는 셋뿐이다 — 대입(ASSIGN, 현행 `tp_value_cast` 명시 모드: 반올림·인쇄·절단 검사; 대입 자리와 CAST 소비자 슬롯) · 비교(COMPARE, 현행 `tp_value_coerce_strict`; 술어와 인덱스 키가 공유해야 순차 스캔과 인덱스 스캔의 답이 같다) · 피연산자(OPERAND, 비교 + NUMERIC ← 실수 허용). leaf 는 `object_domain.c` 두 큰 함수의 "목표 타입 switch → 원 타입 switch" 안쪽 본문을 뽑은 것이며, 두 큰 함수는 switch 를 유지한 채 **같은 leaf 를 부른다**(동작 불변 리팩토링 커밋 1개, 단독으로 양 빌드 green + optdebug CTP sql 전수 무 diff). 숫자×숫자·문자→숫자 부류는 템플릿 특수화 + 컴파일 시점 표(빠진 셀 = 컴파일 오류), 문자·날짜·ENUM·컬렉션·JSON 셀은 정적 함수로 기계 추출한다. 표는 `domain_convert_table[3][DB_TYPE_LAST + 1][DB_TYPE_LAST + 1]`(`.rodata` 약 40KB, 빈 셀은 `tp_value_convert_incompatible`), 조회는 로드·게이트·휘발 항목에서만이고 행 루프는 항목에 고정된 포인터를 부른다. leaf 는 `TP_DOMAIN_STATUS` 만 돌려주고 `er_set` 은 실패 정책을 아는 호출자가 한다; NULL 원 값은 leaf 밖에서. 결정 원문: #325 D-325-01~08, 정본 `docs/research/domain-pin-converters.md`.

## Considered Options

- **변환 구현을 새로 한 벌 쓴다(게이트 전용 표)**: 기각. 변환 의미가 두 벌(P6)이 되어 CAST/대입 경로와 게이트 경로의 답이 갈린다.
- **셀을 `tp_value_cast`/`tp_value_coerce` 래퍼로**: 기각. 셀 안에서 타입 switch 를 다시 타므로 행당 타입 판정 0(P4, cpp-perf-rules A61·BR-06)을 만족하지 못한다.
- **전부 템플릿**: 기각(사용자 결정 2026-09-22). 고유 로직 셀(문자·날짜·ENUM·컬렉션·JSON)에 템플릿은 본문 수를 줄이지 못하고 읽기만 해친다. 런타임 비용은 두 방식이 같다(셀 = 비제네릭 함수 하나, 간접 호출 1회).
- **문맥(`DOMAIN_CTX`) 9종을 표 인덱스로**: 기각. 실패 정의만 다르고 성공 값은 같은 셋으로 사상된다(D-325-01).
- **압축 인덱스(사용 타입 20종)**: 측정 뒤 변형(escape hatch). 단순함 우선.

## Consequences

- **검수 범위는 leaf 본문이 아니라 leaf 에서 도달 가능한 호출 경로 전체**다(#325 리뷰 S1): `numeric_db_value_coerce_from_num[_strict]`·`numeric_coerce_*` 아래의 목표/원 타입 switch 도 타입 고정 하위 연산으로 추출해 공유한다. grep 게이트는 leaf 이름과 그 피호출 함수 목록을 함께 본다.
- #325 정적 리뷰의 셀 계약 보완 6건은 #328(D-328-02~07, 2026-09-22)이 이 ADR 의 원칙 안에서 정했고 `domain-pin-converters.md` §0b·§1~§3·§7 이 그 정본이다: **R1** 절단 셀 3종(문자→문자(n)·문자→비트(n)·비트→비트(n))은 절단 값을 남기고 `DOMAIN_TRUNCATED`(leaf 만 돌려주는 `TP_DOMAIN_STATUS` 값)를 반환하며, 수용 여부는 항목 플래그 `TRUNCATE_OK`(사용자 CAST 의 비슬롯 피연산자 = 현행 `tp_value_cast_force`) 또는 게이트가 읽은 `allow_truncated_string`(대입·STRICT 시그니처 CAST·CAST 아래 슬롯 = 현행 바인드 캐스트)이 정한다; VARCHAR→CHAR(n) 항등은 비교·피연산자 모드만. **R2** `RESOLVED_DOMAIN.operand_domain[3]` — 변환기는 피연산자별 목표에 대해 조회하고 `domain` 은 결과만 뜻한다. **R3** 게이트 의존 노드 안의 사전 캐스트(날짜×실수/문자 → BIGINT 등)는 대입 모드(현행 `tp_value_auto_cast` = ROUND), 피연산자 모드(strict)는 컴파일 미러 슬롯에만. **R4** 비교 모드 leaf 는 KEEP 판정에만 쓰고, KEEP 뒤 행 비교 변환기는 대입 모드 셀(현행 `tp_value_coerce` 와 도달 셀에서 동일). **R5** 값 부류 오버로드 자리는 게이트가 `domain_classify_value` 로 `val_type` 을 먼저 분류하고 `domain_resolve` 는 타입만 본다. **R6** 비교 모드가 닿는 날짜·NUMERIC 파서는 상태 전용 코어와 `er_set` 래퍼로 나누고, KEEP 직후 잔류 오류 0 을 assert 한다. 원칙(3 모드·공유 leaf·정적 표·상태 반환)은 바뀌지 않았다; 신규 답안 변경 0.
- leaf 프로토타입은 새 헤더 `object/object_domain_convert.h`(`object_domain.c` 와 `query/domain_resolver.c` 만 포함)에 둔다 — `object_domain.h` 의 CCD 를 늘리지 않는다(PHYS-02).
- 되돌리는 길: 리팩토링 커밋은 동작 불변이므로 단독 revert 가 가능하고, 그 위의 게이트 코드는 표 대신 `tp_value_cast_preserve_domain`/`tp_value_coerce_strict` 를 직접 부르는 임시 어댑터로 살 수 있다(행당 타입 판정 0 은 잃는다).
