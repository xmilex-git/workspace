---
status: proposed
date: 2026-09-29
locked-by: xmilex-git/workspace#374 (D-374-03·04·20·21·27, 2026-09-29)
supersedes: ADR 0022 (accepted 뒤)
---
# 변환기는 템플릿 특수화이고, switch 하나가 변환기를 찾는다 — 캐스트·strict 강제·확정 변환기가 모두 같은 switch 를 쓴다

변환기는 `tp_value_convert<SRC, DST, MODE>` 같은 템플릿이다. 기본은 INCOMPATIBLE 이고, 변환되는 (원 타입, 목표 타입) 쌍만 특수화한다. 모드는 넷이다: 대입(ASSIGN)·암시(IMPLICIT, 현행 `tp_value_cast_internal` 의 컬렉션 원소 암시 변환)·비교(COMPARE, strict)·피연산자(OPERAND).

(모드, 원 타입, 목표 타입)을 변환기로 바꾸는 곳은 `tp_value_find_converter` 의 switch 하나다. 변환하는 쌍만 `case` 로 적고 나머지는 공유 incompatible 함수를 돌려준다. 네 모드는 같은 `case` 목록의 인스턴스다. 표는 두지 않는다. 손으로 쓴 3차원 표 리터럴도, 템플릿에서 생성한 표(`std::index_sequence`, 옛 `tp_numeric_convert_table` 포함)도 없다.

- 실행 전 도메인 확정과 로드가 확정 변환기를 한 번 찾고, 행은 그 함수 포인터만 부른다.
- `tp_value_cast_internal`·`tp_value_coerce_strict` 에는 앞뒤 처리(도메인 선택, NULL·JSON, 절단 수용, 오류 코드)만 남기고, 쌍의 매핑은 같은 switch 를 부른다(SSOT).
- 코드는 한 번역 단위 `src/object/object_domain_convert.cpp` 에 둔다. 템플릿이 `.c` 에 있으면 CI 의 GNU indent 2.2.11 이 뒤 코드를 망가뜨리고, cpp-perf-rules CPP-09 도 `.c` 파일의 템플릿을 권하지 않는다.
- 호출 이름은 `tp_value_convert`(실행), 함수 포인터 타입은 `TP_VALUE_CONVERTER` 다.

이유:
- ADR 0022 의 구현은 같은 매핑을 세 벌 두었다: 두 캐스트 함수의 `switch` 와 3차원 표. 게다가 쌍마다 추출 부산물이 붙어 `object_domain.c` 가 12,272 → 31,756줄이 됐다. 늘어난 19,484줄 가운데 약 15,700줄은 로직이 아니다: 래퍼 2,304, 전방 선언 474, 표 리터럴 5,369, 이름 표 1,141, 빈 줄과 case 틀 6,391(#374 F-374-02~04).
- ADR 0022 가 "전부 템플릿" 을 기각한 이유는 고유 로직에 템플릿이 본문 수를 줄이지 못한다는 것이었다. 그 판단은 그대로다 — 쌍마다 다른 로직(약 4,300줄)은 특수화 하나씩으로 남는다. 템플릿이 없애는 것은 쌍마다 붙은 래퍼·틀·선언·표다.

## Considered Options

- **템플릿에서 표를 생성(#374 라운드 1 Q6 (가))**: 기각(사용자 선택 (다), 2026-09-29). switch 코드가 매핑을 그대로 보여 준다. 메타프로그래밍 없이 원래 CUBRID 개발자가 읽을 수 있다. 행 비용은 같다.
- **행마다 switch 로 템플릿을 고른다((나))**: 기각. 행 루프 안의 재디스패치다(cpp-perf-rules BR-06·A59·A61). BR-06 의 trade-off note 가 권하는 것은 행 전에 한 번 고른 함수 포인터 호출이다.
- **변환기 없이 행이 `tp_value_cast_internal` 을 모드와 함께 부른다(구조 리뷰 O1)**: 기각. 행에서 값 타입으로 변환 함수를 다시 고르게 된다(P4 "행은 확정하지 않는다").
- **지금 구조를 두고 표·래퍼만 압축(구조 리뷰 O2 의 생성 표 판)**: 위 첫 항목과 같은 이유로 기각.

## Consequences

- `tp_value_cast_internal`·`tp_value_coerce_strict` 는 호출마다 switch 와 간접 호출이 한 번씩 든다. 지금은 switch 와 직접 호출이다. develop 코드도 행마다 부르는 함수라 명령 수로 잰다(PR 머리 대비 +1% 이내, develop 대비 +5% 이내, D-374-30). 나쁘면 같은 `case` 목록으로 직접 호출을 만드는 방문자(visitor) 템플릿으로 바꾼다. 그래도 SSOT 는 유지된다.
- 셀·표·이름 표 없이 변환기를 부르는 곳은 `tp_value_convert` 하나다. 플랜 덤프와 optdebug 교차 검사는 변환기 이름을 찍지 않는다(D-374-02).
- 되돌리는 길: 이 재작성은 동작 불변 커밋 하나다. 문제가 있으면 그 커밋만 되돌려 ADR 0022 구조로 돌아간다.
