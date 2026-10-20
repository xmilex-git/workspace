---
status: accepted
date: 2026-10-20
issue: CBRD-27668
---

# 타입 없는 NULL 만 있는 행·가지는 열 타입을 정하지 않고, 열 자리의 NULL 캐스트는 상수 접기에서 타입을 잃지 않는다

VALUES 의 첫 행이나 집합 연산·재귀 CTE 의 첫 가지가 `null` 이면 열 타입이 NULL 로 정해져, VALUES 뒤 행의 값이 NULL 이 되고(`(values (null),(2))` → NULL, NULL), IN + UNION 이 0 행, 재귀 CTE 가 끝나지 않았다(10.2~11.5 모두). 원인은 둘이다. (1) `pt_union_compatible` 이 NULL 을 어떤 타입과도 호환으로 보아 캐스트를 넣지 않는다. (2) 의미 검사가 NULL 쪽에 `CAST(NULL AS T)` 를 넣어도 `pt_semantic_type` 이 타입 검사 뒤에 하는 상수 접기(`pt_fold_const_expr`)가 그것을 타입 없는 NULL 값으로 바꾼다 — 11.4 이하는 값마다 타입을 지녀 대부분 가려졌고, 11.5 는 리스트 열 도메인을 그 노드에서 가져와 값이 사라진다(`(values (null),(2),(3.5)) where a = 2`: 11.4.6 `2.0`, develop 0 행). 2026-10-20 그릴링(Q1~Q9, 사용자 전부 추천안)에서 다음을 정했다. 이 원칙은 CBRD-27583 에서 사양 변경 16 으로 정했다가 철회해 이 이슈로 넘긴 것이다(ADR 0028).

- **열 타입은 NULL 이 아닌 쪽이 정한다.** 타입 없는 NULL 만 있는 행·가지는 열 타입을 정하지 않는다. 열 타입은 NULL 이 아닌 행·가지끼리 지금 규칙으로 합친 타입이고, NULL 쪽을 그 타입으로 캐스트한다. NULL 이 아닌 쪽이 하나면 그 도메인을 그대로 쓴다(CHAR(3)·NUMERIC(3,2) 그대로; 합치기 함수를 거치면 CHAR→VARCHAR, develop 은 NUMERIC(38,15)가 된다). 모두 NULL 인 열은 NULL 타입 그대로다. 단순 출력(`select null union select 1`)의 답은 바뀌지 않는다.
- **빠지는 타입.** 상대가 바인드 `?`, OBJECT, 컬렉션, ENUM 이면 지금처럼 캐스트하지 않는다 — 호환 정보가 클래스·원소 도메인을 담지 못하고, 캐스트 함수가 ENUM·컬렉션은 상대 쪽까지 다시 캐스트한다.
- **열 자리의 NULL 캐스트는 접지 않는다.** 위 규칙이 넣는 캐스트, 그리고 사용자가 쓴 `CAST(NULL AS T)` 가 VALUES 행·집합 연산 가지·재귀 CTE 두 부분의 열 자리에 있을 때 표시를 붙이고, 상수 접기는 표시된 CAST 의 NULL 인자를 접지 않는다. 그래서 호환 검사가 쓴 타입이 실행까지 간다. 다른 자리(WHERE, DEFAULT 등)의 `cast(null as T)` 는 지금처럼 접힌다.
- **재귀 CTE 자기 참조 이름.** 재귀 부분은 비재귀 부분의 타입으로 바인드되므로, 비재귀 부분이 타입 없는 NULL 이고 재귀 부분이 열 타입을 정하면 자기 참조 이름(`k`)이 NULL 타입으로 남아 상수 접기가 `k is null` 을 참으로 바꿨다(무한 재귀). 최종 열 타입이 정해진 뒤 그런 이름은 최종 타입을 받는다.
- **모두 NULL 인 열과 상수의 비교**(Q10, 2026-10-20 사용자 추천안 수락). 파생 테이블·CTE 의 열이 타입 없는 NULL 뿐이면 그 열은 NULL 타입이고, 상수와 비교할 때 상수를 NULL 타입으로 캐스트하다 -181 이 났다(`select * from (select null a) t where a = 2`, 모든 버전). CBRD-26845 가 NA 열에 둔 예외처럼 상수 쪽에서 추론한 타입으로 비교하고 결과는 UNKNOWN 이다. JIRA 재현 4 의 둘째 질의(`select null union all select k + 1 from r where k < 3` → NULL)가 여기에 걸린다. develop PR 의 둘째 커밋이고 백포트 때 함께 가져가며, NA 예외가 없는 10.2~11.3 은 손으로 맞춘다.
- **백포트.** 고치는 함수는 release/10.2·11.0·11.2·11.3·11.4 에서 같다. develop PR 의 첫 커밋 하나가 위 수정을 모두 담아 다섯 브랜치에 그대로 cherry-pick 되게 하고, 11.5 전용 수정이 생기면 따로 커밋한다. 백포트는 develop 머지 뒤 진행한다.

## Considered Options

- **NULL 쪽에 캐스트만 넣기**(JIRA 분석 원안): 단독으로는 기각. 접기가 캐스트를 지워 develop 에서 고쳐지지 않는다(develop 은 `(values (null),(2),(3.5))` 에서 이미 첫 행에 캐스트를 넣는데도 세 행이 NULL).
- **모든 `CAST(NULL AS T)` 를 접지 않기**: 기각. 사용자가 쓴 타입 있는 NULL 전부의 컴파일이 바뀐다 — `where a = cast(null as int)` 가 상수 거짓(플랜 없음)에서 스캔으로 바뀌고, DEFAULT 등 DDL 경로를 다시 확인해야 하며, 그 위험이 다섯 브랜치 백포트에 실린다.
- **NULL 쪽 캐스트 타입을 기존 합치기 함수(`pt_update_compatible_info`)로 정하기**: 기각. NULL 이 아닌 쪽 타입이 바뀐다(CHAR→VARCHAR, develop NUMERIC(38,15)) — 지금 맞게 나오는 출력 타입이 달라진다.
- **생성(XASL)이 NULL 형 가지 열에 통일 도메인을 주기**(CBRD-27583 D-90 방식): 기각. 그 이슈의 재작성 위에서만 성립해 백포트할 수 없고, 컴파일 타입(IN 비교, 재귀 CTE 재귀 부분)이 이미 틀린 경우를 고치지 못한다.

## Consequences

- 사용자가 열 자리에 쓴 `cast(null as int)` 는 열 자리에서 INT 로 남는다: `i in (select cast(null as int) union select 1)` 가 1 을 내고, 11.5 에서만 틀리던 `(values (cast(null as int)), (2))` 가 11.4 와 같은 `NULL, 2` 가 된다. `select * from (select cast(null as int) a union all select 'x') t` 의 -181 은 그대로다.
- CBRD-27583 은 이 이슈가 develop 에 머지된 뒤 rebase 할 때 이 답을 따른다(ADR 0028 사양 변경 16 철회 항목).
