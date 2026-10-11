# A9 — PR #8022 본문 수정안 (게시 전 확인용)

현재 본문에서 코드와 어긋나거나 용어집(`CONTEXT.md`)의 _Avoid_ 이름을 쓰는 문장만 바꾼다. 나머지(Remarks 의 스펙 변경·오류 코드·성능 표·테스트)는 그대로.

| 위치 | 현재 | 수정 |
|---|---|---|
| Purpose 2번째 bullet | "값이 있어야 정해지는 자리는 GATE 슬롯으로 표시합니다." | "값이 있어야 정해지는 자리(가변 POS)는 `tp_Variable_domain` 으로 싣습니다." |
| Purpose 3번째 bullet | "계획에는 슬롯, 피연산자 부류, 게이트에 의존하는 노드, 비교 자리, 인덱스 키가 들어갑니다. 실행마다 `qexec_execute_mainblock` 직전의 게이트(`qexec_resolve_domains`)가 바인드 값의 타입으로 이 모두를 한 번 정합니다." | "계획에는 가변 POS, 피연산자 부류, 늦은 바인딩 노드, 확정 비교, 인덱스 키가 들어갑니다. 실행마다 `qexec_execute_mainblock` 직전에 `qexec_resolve_domains` 가 바인드 값의 타입으로 이 모두를 한 번 확정합니다(실행 전 도메인 확정)." |
| Purpose 4번째 bullet | "결정은 `XASL_STATE`(`RESOLVED_DOMAIN`)에만 두고" | "확정은 `XASL_STATE`(확정 도메인 표 `resolved_domain`, 실행 도메인 `domain_execution`)에만 두고" |
| Purpose 5번째 bullet | "결정을 읽고, 행에 필요한 변환은 계획된 변환기(변환 표의 셀 함수)로만 합니다. 행마다 도메인을 정하던 코드와 clone 도메인 복원 코드는 삭제했습니다." | "확정을 읽고, 행에 필요한 변환은 확정 변환기(`tp_value_find_converter` 가 고른 함수 포인터)로만 합니다. 행마다 도메인을 정하던 코드와 clone 도메인 복원 코드는 삭제했습니다." |
| Implementation "도메인 해석기" | "`domain_resolver.c/h`: … 비교 기록과 키 쌍 표도 여기서 만듭니다." | "`domain_rules.c/h`: … 확정 비교와 타입 쌍 비교 표도 여기서 만듭니다." |
| Implementation "게이트 — `query_executor.c`" | 제목 "게이트"; "`qexec_resolve_domains` 가 슬롯, 게이트 의존 노드, 세션변수 타입, 상수 부분트리, 비교, 인덱스 키를 결정합니다." | 제목 "실행 전 도메인 확정 — `domain_resolve.c`, `query_executor.c`"; "`qexec_resolve_domains` 가 가변 POS, 늦은 바인딩 노드, 세션변수 문장 타입, 상수식, 확정 비교, 인덱스 키를 확정합니다." |
| 같은 절, XASL 캐시 키 bullet | "게이트가 develop 의 튜플 캐스트로 한 번 바꿉니다." | "실행 전 확정이 develop 의 튜플 캐스트로 한 번 바꿉니다." |
| Implementation "컴파일" | "GATE 비트를 붙입니다." | "기대 도메인이 없는 POS 의 도메인을 `tp_Variable_domain` 으로 싣습니다(로드가 `REGU_VARIABLE_VARIABLE_DOMAIN`·`DOMAIN_PLAN_LATE_BIND` 를 도출합니다)." |
| Remarks 새 오류 코드 | "`ER_QPROC_DOMAIN_UNRESOLVED`(-1383)는 계획과 실행의 경계 위반입니다." | "`ER_QPROC_DOMAIN_UNRESOLVED`(-1383)는 미확정 도메인 오류(계획이 정했어야 할 도메인이 없을 때)입니다." |

적용 방법: `gh pr view 8022 --json body --jq .body > body.md` → 위 치환 → `gh pr edit 8022 --body-file body.md`. #377 의 코드 변경(A1~A7)이 머리에 들어가면 Implementation 절에 "`domain_state.h`(XASL_STATE 의 실행 상태 두 구조체)" 한 줄을 더한다.
