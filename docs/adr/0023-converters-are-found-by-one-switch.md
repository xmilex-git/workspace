---
status: accepted
date: 2026-10-03 (2026-09-29 판 #374 을 최종 구현 기준으로 다시 씀)
basis: CUBRID/cubrid#8022 HEAD 23a5e5561 (develop 15e7dc8b5 동기화)
locked-by: xmilex-git/workspace#374 D-374-03·04·20·21·27·37·40·41 (2026-09-29, 커밋 7541abcc2)
---
# 변환기는 쌍마다 이름 있는 함수이고, switch 하나(`tp_value_find_converter`)가 찾는다 — 행은 찾아 둔 함수 포인터만 부른다

변환기는 (원 타입, 목표 타입) 쌍마다 이름 있는 함수다(`tp_value_convert_char_to_date`). strict 로 따로 변환하는 쌍은 `_strict` 함수를 하나 더 가진다. 템플릿은 중복을 실제로 없애는 곳에만 쓴다: 숫자 쌍은 `tp_value_convert_number<SRC, DST, MODE>` 한 벌, 컬렉션 변환은 목표 컬렉션과 암시 여부를 인자로 받는 템플릿 한 벌이다. (모드, 원 타입, 목표 타입)을 변환기로 바꾸는 곳은 `tp_value_find_converter (src_type, desired_domain, mode)` 의 switch 하나다 — 변환하는 쌍만 `case` 로 적고, 모드에 따라 고르는 곳은 `case` 안의 `strict ? a : b` 로 보이며, 나머지는 공유 incompatible 함수를, 같은 타입은 `nullptr`(변환 없음)을 돌려준다. 표는 두지 않는다(손으로 쓴 3차원 표 리터럴도, 템플릿이 생성한 표도). 로드 도출과 실행 전 도메인 확정이 변환기를 한 번 찾아 도메인 계획 항목·확정 도메인 표·확정 비교·키 원소에 두고, 행은 그 포인터만 부른다(`tp_value_convert`, 인라인). `tp_value_cast_internal`·`tp_value_coerce_strict` 에는 앞뒤 처리(도메인 선택, NULL·JSON, 절단 수용, 오류 코드)만 남고 쌍의 매핑은 같은 switch 를 부른다. 코드는 한 번역 단위 `src/object/object_domain_convert.cpp` 에 둔다 — 템플릿이 `.c` 에 있으면 CI 의 GNU indent 2.2.11 이 뒤 코드를 망가뜨린다(cpp-perf-rules CPP-09).

이유: 2026-09-22 판(ADR 0022 초판)의 구현은 같은 매핑을 세 벌 두었다 — 두 캐스트 함수의 switch 와 3차원 정적 표 `domain_convert_table[3][DB_TYPE_LAST + 1][DB_TYPE_LAST + 1]`. 쌍마다 추출 부산물(래퍼 2,304줄, 전방 선언 474, 표 리터럴 5,369, 이름 표 1,141, 빈 줄과 case 틀 6,391)이 붙어 `object_domain.c` 가 12,272 → 31,756줄이 됐다(F-374-02~04). 쌍마다 다른 로직(약 4,300줄)만 쌍마다 함수 하나로 남는다.

## Considered Options

- **쌍마다 템플릿 특수화**(`tp_value_converter<SRC, DST, MODE>`, #374 첫 판): 기각(사용자 (나), D-374-37). 모드를 템플릿 인자로 두면 모드와 무관한 변환기 약 119개가 모드마다 따로 인스턴스화되어 같은 기계어가 3벌 생긴다(I-cache). 이름 있는 함수는 grep 으로 찾히고 CUBRID 개발자가 그대로 읽는다.
- **템플릿에서 표를 생성**(`std::index_sequence`): 기각(사용자 (다)). switch 코드가 매핑을 그대로 보여 주고, 행 비용은 같다.
- **행마다 switch 로 변환기를 고른다**: 기각. 행 루프 안의 재디스패치다(BR-06·A59·A61).
- **변환기 없이 행이 `tp_value_cast_internal` 을 모드와 함께 부른다**: 기각. 행에서 값 타입으로 변환 함수를 다시 고르게 된다.
- **같은 `case` 목록으로 직접 호출을 만드는 방문자(visitor) 템플릿**: 측정 뒤 **되돌림**. 변환기 본문이 switch 안에 인라인되어 스택 프레임이 커졌고 P2·P3·P4 셀이 나빠졌다.

## Consequences

- `tp_value_cast_internal`·`tp_value_coerce_strict` 는 호출마다 switch 와 간접 호출이 한 번씩 든다. 명령 수로 재어 PR 머리 대비 +1% 이내·develop 대비 +5% 이내(D-374-30). 리터럴을 캐스트하는 7칸(P2-expr, P3-agg, P4-topn, P6-in L)은 1.2~2.4% 많고 사용자가 수용했다(D-374-41). 행마다 변환기를 찾던 CAST 노드는 로드가 변환기를 행 전에 고정한다(`fetch_cast_operand`, D-374-40).
- 변환기를 부르는 곳은 `tp_value_convert` 하나다. 플랜 덤프와 optdebug 교차 검사는 변환기 이름을 찍지 않는다(D-374-02).
- 캐스트가 develop 과 같은 오류를 내려고 남긴 앞뒤 처리: 문자열 → NUMERIC 파싱 넘침은 er_set 과 DOMAIN_ERROR(확정 변환기는 DOMAIN_OVERFLOW), BIT·VARBIT 목표의 incompatible 쌍은 `db_bit_string_coerce` 의 오류, CLOB → 문자열의 src == dest, `tp_value_coerce_strict` 의 ENUM·JSON 원본 거절(비교 변환기는 `tp_value_compare` 처럼 변환한다).
- 되돌리는 길: 재작성은 동작 불변 커밋 하나라 그 커밋만 되돌리면 2026-09-22 판 구조(세 벌 매핑)로 돌아간다.
