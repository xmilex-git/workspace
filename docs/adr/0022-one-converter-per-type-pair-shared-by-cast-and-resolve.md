---
status: accepted
date: 2026-10-03 (2026-09-22 판 #320 "셀 함수 3-모드 정적 표" 를 최종 구현 기준으로 다시 씀; 표·셀·leaf 는 ADR 0023 에서 switch·변환기로 바뀌었다)
basis: CUBRID/cubrid#8022 HEAD 23a5e5561 (develop 15e7dc8b5 동기화)
locked-by: xmilex-git/workspace#320 (2026-09-22) · #328 D-328-01~07 (2026-09-22) · #374 F-374-02 (2026-09-29)
---
# 변환기는 (원 타입, 목표 타입, 변환 모드)가 고정된 함수 하나이고, 캐스트·strict 강제·확정 변환기가 같은 변환기를 부른다 (모드 넷, 상태만 반환, er_set 은 호출자)

변환기(`TP_VALUE_CONVERTER`)는 `tp_value_cast_internal`·`tp_value_coerce_strict` 의 "목표 타입 switch → 원 타입 switch" 안쪽 case 본문을 뽑은 함수 하나로, 안에서 값 타입을 다시 판정하지 않고 `TP_DOMAIN_STATUS` 만 돌려준다. 변환 모드(`DOMAIN_CONVERT_MODE`)는 넷이다 — **대입**(ASSIGN: `tp_value_cast` 의 명시 모드, 정수 목표 반올림·인쇄·절단 검사; 대입 자리·CAST 노드 아래 POS·늦은 바인딩 노드 안의 피연산자 변환) · **암시**(IMPLICIT: `tp_value_coerce` — 암시 강제가 허락하지 않는 쌍은 incompatible, 컬렉션은 원소를 암시로) · **비교**(COMPARE: `tp_value_coerce_strict`, 손실이면 실패; 술어와 인덱스 키가 공유해야 순차 스캔과 인덱스 스캔의 답이 같다) · **피연산자**(OPERAND: 비교 + NUMERIC ← 실수 허용; 산술·함수 인자·집계·공통값·리스트 컬럼). 모드는 변환 실패의 정의만 다르고 성공 값은 같다. 클라이언트 캐스트(`tp_value_cast_preserve_domain` → `tp_value_cast_internal`), 서버의 strict 강제, 로드 도출·실행 전 확정이 고정하는 확정 변환기가 전부 같은 변환기를 부르므로 변환 의미는 한 벌이다. `er_set` 은 실패 정책을 아는 호출자가 한다 — `tp_value_cast_internal` 은 날짜·시간 변환 오류(`date_conversion_error`)를 발행하고, 행의 `tp_value_convert` 는 기록된 DOMAIN_ERROR 를 DOMAIN_INCOMPATIBLE 로 돌려준다. NULL 원 값은 변환기 밖에서 목표 도메인의 typed NULL 이다. 비교가 어느 쪽을 먼저 변환하는지(`TP_COMPARE_COERCION`)도 `tp_value_compare_with_error` 와 도메인 해석기가 한 정의를 공유한다.

결정 원문: #325 D-325-01~08, #328 D-328-01~07, #374 F-374-02·D-374-03·04. 정본: `docs/research/domain-pin-converters.md`.

## Considered Options

- **실행 전 확정 전용 변환 표를 새로 쓴다**: 기각. 변환 의미가 두 벌이 되어 CAST/대입 경로와 확정 경로의 답이 갈린다.
- **변환기를 `tp_value_cast`/`tp_value_coerce` 래퍼로**: 기각. 안에서 타입 switch 를 다시 타므로 행당 타입 판정 0(cpp-perf-rules A61·BR-06)을 만족하지 못한다.
- **문맥(`DOMAIN_CTX`) 9종을 모드로**: 기각. 실패 정의만 다르고 성공 값은 같은 넷으로 사상된다.
- **모드 셋**(2026-09-22 판): `tp_value_cast_internal` 의 암시 강제(컬렉션 원소를 암시 변환)가 셋 중 어디에도 없어 넷이 됐다(F-374-02).
- **변환기 안에서 `er_set`**: 기각. KEEP 판정(비교 모드로 1회 묻고 실패면 원 도메인 유지)은 오류 없이 돌아와야 한다 — 변환기가 부르는 날짜·NUMERIC 파서는 상태만 돌려주는 코어(`tp_atodate_core` 등)와 `er_set` 래퍼로 나눴다(D-328-07).

## Consequences

- 피연산자 목표 도메인: 타입 규칙은 결과 도메인과 별도로 피연산자마다 변환 목표를 내고(`RESOLVED_DOMAIN.operand_domain[3]`·`conv[3]`), 변환기는 그 목표에 대해 고른다 — 날짜 + 정수처럼 연산이 이종 입력을 받으면 결과 도메인과 다르다(D-328-03). SUM/AVG 의 피연산자 변환은 `DOMAIN_OPERAND_COERCION` 으로 셋업 때 고정한다.
- KEEP 판정 뒤 행 비교의 변환기는 대입 모드 변환기다(`tp_value_coerce` 와 도달 변환기가 같다, D-328-05). 늦은 바인딩 노드 안의 사전 변환(날짜×실수 → BIGINT 등)도 대입 모드(`tp_value_auto_cast` = ROUND, D-328-04).
- 절단 수용: 문자·비트를 짧은 도메인으로 바꾸는 변환기는 절단 값과 `DOMAIN_TRUNCATED` 를 돌려주고, 수용 여부는 호출자가 정한다(사용자 CAST 의 컬럼·식 피연산자는 수용, 대입·시그니처 CAST·CAST 아래 POS 는 `allow_truncated_string`, D-328-02).
- 검수 범위는 변환기 본문이 아니라 변환기에서 도달하는 호출 경로 전체다(`numeric_db_value_coerce_from_num[_strict]` 아래의 타입 switch 포함, D-328-01).
- 프로토타입은 `object/object_domain_convert.h` 에 두어 `object_domain.h` 의 포함 비용을 늘리지 않는다(PHYS-02).
- 되돌리는 길: 추출은 동작 불변 리팩토링이라 그 커밋만 되돌릴 수 있고, 그 위의 확정 코드는 `tp_value_cast_preserve_domain`/`tp_value_coerce_strict` 를 직접 부르는 어댑터로 산다(행당 타입 판정 0 은 잃는다).
