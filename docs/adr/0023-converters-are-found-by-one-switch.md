---
status: accepted (2026-09-29, #374 커밋 2 `7541abcc2` 게이트 통과)
date: 2026-09-29
locked-by: xmilex-git/workspace#374 (D-374-03·04·20·21·27·37, 2026-09-29)
supersedes: ADR 0022 (accepted 뒤)
---
# 변환기는 쌍마다 이름 있는 함수이고, switch 하나가 변환기를 찾는다 — 캐스트·strict 강제·확정 변환기가 모두 같은 switch 를 쓴다

변환기는 (원 타입, 목표 타입) 쌍마다 이름 있는 함수다(`tp_value_convert_char_to_date`). strict 로 따로 변환하는 쌍은 `_strict` 함수를 하나 더 가진다. 템플릿은 중복을 실제로 없애는 곳에만 쓴다: 숫자 쌍은 `tp_value_convert_number<SRC, DST, MODE>` 한 벌이고, 컬렉션 변환은 목표 컬렉션과 암시 여부를 인자로 받는 템플릿 한 벌이다. 모드는 넷이다: 대입(ASSIGN)·암시(IMPLICIT, `tp_value_coerce` 의 변환: 암시 강제가 허락하지 않는 쌍은 incompatible, 컬렉션은 원소를 암시로 변환)·비교(COMPARE, strict)·피연산자(OPERAND).

(모드, 원 타입, 목표 타입)을 변환기로 바꾸는 곳은 `template <DOMAIN_CONVERT_MODE MODE> tp_value_find_converter` 의 switch 하나다. 변환하는 쌍만 `case` 로 적고, 모드에 따라 고르는 곳은 `case` 안에서 `strict ? a : b` 로 보인다. 나머지는 공유 incompatible 함수를, 같은 타입은 `nullptr`(변환 없음)을 돌려준다. 네 모드는 같은 `case` 목록의 인스턴스다. 표는 두지 않는다. 손으로 쓴 3차원 표 리터럴도, 템플릿에서 생성한 표(`std::index_sequence`, 옛 `tp_numeric_convert_table`)도 없다.

- 실행 전 도메인 확정과 로드가 확정 변환기를 한 번 찾고, 행은 그 함수 포인터만 부른다(`tp_value_convert`).
- `tp_value_cast_internal`·`tp_value_coerce_strict` 에는 앞뒤 처리(도메인 선택, NULL·JSON, 절단 수용, 오류 코드)만 남기고, 쌍의 매핑은 같은 switch 를 부른다(SSOT).
- 코드는 한 번역 단위 `src/object/object_domain_convert.cpp` 에 둔다. 템플릿이 `.c` 에 있으면 CI 의 GNU indent 2.2.11 이 뒤 코드를 망가뜨리고, cpp-perf-rules CPP-09 도 `.c` 파일의 템플릿을 권하지 않는다.
- 호출 이름은 `tp_value_convert`(실행), 함수 포인터 타입은 `TP_VALUE_CONVERTER` 다. 변환기는 날짜 변환 오류 기록(`date_conversion_error`)을 받는다. `tp_value_cast_internal` 은 그 오류를 발행하고, `tp_value_convert` 는 오류가 기록된 DOMAIN_ERROR 를 DOMAIN_INCOMPATIBLE 로 바꾼다(옛 래퍼 300개가 하던 일).

이유:
- ADR 0022 의 구현은 같은 매핑을 세 벌 두었다: 두 캐스트 함수의 `switch` 와 3차원 표. 게다가 쌍마다 추출 부산물이 붙어 `object_domain.c` 가 12,272 → 31,756줄이 됐다. 늘어난 19,484줄 가운데 약 15,700줄은 로직이 아니다: 래퍼 2,304, 전방 선언 474, 표 리터럴 5,369, 이름 표 1,141, 빈 줄과 case 틀 6,391(#374 F-374-02~04).
- 쌍마다 다른 로직(약 4,300줄)은 쌍마다 함수 하나로 남는다. 템플릿이 줄이는 것은 로직이 같은 계열(숫자 쌍 57개 × 모드, 컬렉션 세 종류 × 암시 여부)이다.

## Considered Options

- **쌍마다 템플릿 특수화(`tp_value_converter<SRC, DST, MODE>`, 이 ADR 의 첫 판)**: 기각(사용자 (나), 2026-09-29, D-374-37). 모드를 템플릿 인자로 두면 모드와 무관한 셀 약 119개가 모드마다 따로 인스턴스화되어 같은 기계어가 3벌 생긴다(CPP-09, I-cache). 이를 피하려면 쌍 특수화에 모드 선택 traits 를 더해야 해 메타프로그래밍이 는다. 이름 있는 함수는 grep 으로 찾히고 CUBRID 개발자가 그대로 읽는다.
- **템플릿에서 표를 생성(#374 라운드 1 Q6 (가))**: 기각(사용자 (다)). switch 코드가 매핑을 그대로 보여 준다. 메타프로그래밍 없이 읽힌다. 행 비용은 같다.
- **행마다 switch 로 변환기를 고른다((나))**: 기각. 행 루프 안의 재디스패치다(cpp-perf-rules BR-06·A59·A61). BR-06 의 trade-off note 가 권하는 것은 행 전에 한 번 고른 함수 포인터 호출이다.
- **변환기 없이 행이 `tp_value_cast_internal` 을 모드와 함께 부른다(구조 리뷰 O1)**: 기각. 행에서 값 타입으로 변환 함수를 다시 고르게 된다(P4 "행은 확정하지 않는다").

## Consequences

- `tp_value_cast_internal`·`tp_value_coerce_strict` 는 호출마다 switch 와 간접 호출이 한 번씩 든다. 지금은 switch 와 직접 호출이다. develop 코드도 행마다 부르는 함수라 명령 수로 잰다(PR 머리 대비 +1% 이내, develop 대비 +5% 이내, D-374-30). 나쁘면 같은 `case` 목록으로 직접 호출을 만드는 방문자(visitor) 템플릿으로 바꾼다. 그래도 SSOT 는 유지된다.
- 캐스트가 develop 과 같은 오류를 내려고 남기는 앞뒤 처리: 문자열 → NUMERIC 의 파싱 넘침은 er_set 과 DOMAIN_ERROR(확정 변환기는 DOMAIN_OVERFLOW), BIT·VARBIT 목표의 incompatible 쌍은 `db_bit_string_coerce` 의 오류 설정, CLOB → 문자열의 src == dest 처리, `tp_value_coerce_strict` 의 ENUM·JSON 원본 거절(비교 변환기는 tp_value_compare 처럼 변환한다).
- 셀·표·이름 표 없이 변환기를 부르는 곳은 `tp_value_convert` 하나다. 플랜 덤프와 optdebug 교차 검사는 변환기 이름을 찍지 않는다(D-374-02).
- 되돌리는 길: 이 재작성은 동작 불변 커밋 하나다. 문제가 있으면 그 커밋만 되돌려 ADR 0022 구조로 돌아간다.
- 측정 결과(2026-09-29): 방문자(직접 호출) 시도는 변환기 본문이 switch 안에 인라인되어 스택 프레임이 커졌고, P2·P3·P4 가 더 나빠져 되돌렸다. 대신 행마다 변환기를 찾던 캐스트는 로드가 변환기를 행 전에 확정한다(D-374-40, `fetch_cast_operand`). 그래도 리터럴을 캐스트하는 7칸(P2-expr, P3-agg, P4-topn, P6-in L)은 PR 머리보다 명령 수가 1.2~2.4% 많다. 모두 develop 대비 +5% 이내이고, 사용자가 이 상태를 받아들였다(D-374-41, D-374-30 의 예외).
