---
status: accepted
date: 2026-10-30
issue: CBRD-27819
---

# NUMERIC 변환·산술 코드는 외부 소스를 옮기지 않고 알고리즘만 가져와 새로 쓴다

CBRD-27819 survey(workspace #471, D12·D14)는 PostgreSQL `d2s.c`(Ryu)와 `numeric.c` 를 CUBRID 명명으로 옮기고 PostgreSQL License·Ryu Apache-2.0 고지를 남기기로 했고, fork 브랜치 `CBRD-27819-survey` 의 `src/query/numeric_double_decimal.i` 가 그렇게 만들어졌다. 2026-10-30 사용자는 이를 뒤집어, 엔진에 들어가는 코드는 외부 라이선스 고지 없이 CUBRID 자체 구현이어야 한다고 정했다: Ryu·PG 소스는 보고 베끼지 않으며, 논문·설명 수준의 알고리즘(가장 짧은 왕복 십진수, 10000진 산술)만 가져와 CUBRID 코드로 새로 작성한다. 소스 파일·함수 주석에 Ryu·PostgreSQL 출처 고지를 쓰지 않는다(설계 문서는 참고 논문을 인용한다). 새 구현이 이식본보다 느리면, 이식본(survey 브랜치)과 PG 원본을 대조 기준으로만 써서 차이를 좁힌다 — 대조 기준으로 실행·측정하는 것은 허용, 소스를 들여오는 것은 불허.

## Considered Options

- **이식 + 고지 유지(D14)**: 기각. 사용자가 엔진에 외부 라이선스 고지가 남는 것을 원하지 않는다.
- **_dtoa 유지**: 기각. 이슈가 문제 삼은 비용(큰 수 연산·행마다 할당)이 그대로다.

## Consequences

- survey 브랜치의 S1-1(Ryu 이식)은 버리고 자체 구현으로 대체한다. S0·S1-3 은 외부 코드가 없어 그대로 쓴다.
- 자체 구현의 정확성은 이식본·`_dtoa` mode 0 과의 전수 대조(survey 가 쓴 27,964,226 double 하네스)로 증명한다.
