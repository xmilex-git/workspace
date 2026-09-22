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
- #325 정적 리뷰의 셀 계약 보완 6건(R1 CAST 소비자의 CHAR 길이 검사 · R2 피연산자 목표 도메인 ≠ 결과 도메인 · R3 GATE 날짜 산술 사전 캐스트의 ROUND/strict · R4 strict-or-keep 검사 뒤 값 비교용 변환 · R5 값 내용 의존 해석기 입력(MEDIAN/PERCENTILE·STR_TO_DATE·ADDTIME) · R6 KEEP 경로의 무오류 보장)은 이 ADR 의 표 원칙 안에서 **후속 grilling 티켓**이 정하고, 그 결과로 `domain-pin-converters.md` 셀 표를 개정한다. 이 ADR 의 원칙(3 모드·공유 leaf·정적 표·상태 반환)은 그 보완으로 바뀌지 않는다.
- leaf 프로토타입은 새 헤더 `object/object_domain_convert.h`(`object_domain.c` 와 `query/domain_resolver.c` 만 포함)에 둔다 — `object_domain.h` 의 CCD 를 늘리지 않는다(PHYS-02).
- 되돌리는 길: 리팩토링 커밋은 동작 불변이므로 단독 revert 가 가능하고, 그 위의 게이트 코드는 표 대신 `tp_value_cast_preserve_domain`/`tp_value_coerce_strict` 를 직접 부르는 임시 어댑터로 살 수 있다(행당 타입 판정 0 은 잃는다).
