---
status: accepted (amended 2026-09-24 by #335 D-335-10 — see "Amendment")
date: 2026-09-22
locked-by: xmilex-git/workspace#320 (2026-09-22)
---
# 도메인·collation 결정 지점은 컴파일과 실행 게이트 두 곳뿐이다 (플랜 불변, PX 워커 결정 0, 블록 게이트 없음)

질의의 도메인·collation 은 **컴파일(클라이언트 파서 → XASL 스트림)** 과 **실행 게이트 G1(`qexec_resolve_domains`, `qexec_execute_query` 가 값 배열을 만든 직후·`qexec_execute_mainblock` 진입 전, 실행당 1회)** 두 곳에서만 정해지고, 그 뒤 fetch·비교·집계·정렬·키 range·리스트 스캔·PX 워커 어디에서도 값을 보고 도메인을 추론·보정·복원하지 않는다. 컴파일은 기존 도메인 필드를 전부 확정 값으로 채우고(`DB_TYPE_VARIABLE`·`TP_DOMAIN_COLL_LEAVE` 0) 게이트 확정 슬롯만 `regu->flags` 비트 하나(`REGU_VARIABLE_GATE`, placeholder 는 `tp_Variable_domain`; D-323-14, D-325-09)로 표시하며, 슬롯 ID·피연산자 부류(상수·행 의존·상관·휘발)·변환기·게이트 의존 노드 목록은 스트림을 바꾸지 않고 **로드 시 1회 도출**해 불변 `DOMAIN_PLAN` 항목에 둔다(`stx_build_domain_plan`, `qexec_clear_xasl` 순회, 세 로드 경로 공통; D-323-01·17·18). 실행별 답은 XASL_STATE 의 게이트 표 `RESOLVED_DOMAIN` 에만 있고 플랜 노드에는 쓰지 않으며, PX 워커는 `qexec_deep_copy_xasl_state`/`qexec_free_xasl_state` 짝 하나로 값 배열과 게이트 표를 깊은 복사해 상속만 한다(D-323-06). 결정 원문: #312 D-M3, #317 D-317-02·17·18, #318 D-318-01~07, #323 D-323-01~09·13~18, 정본 `docs/research/domain-pin-architecture.md` §1 · `domain-pin-interface.md` v4.

## Considered Options

- **명시 계획 표를 스트림 새 섹션 + 노드마다 `plan_idx` 로 팩**(전략 B): 기각. regu/arith/pred 스트림 레이아웃은 필터 predicate·함수 인덱스 식으로 카탈로그에 저장되는 **디스크 포맷**이라 마이그레이션 없이는 바꿀 수 없고, 도메인의 진실이 노드 필드와 표 두 곳이 된다(P6). B 의 "덤프로 검사 가능" 장점은 로드 도출 결과를 qdump 에 출력해 얻는다(D-323-11; `SHOW TRACE` 불변).
- **서버 게이트가 실행마다 트리 전체에 타입 패스**(전략 C): 기각. 정적 계획에도 매 실행 O(트리) 비용, 파서 격자의 서버 복제, prepare 응답 컬럼 메타 불가 — 이전 캠페인 "잔여 확정" 이 실패한 모양(L-40·L-41).
- **플랜 캐시를 바인드 타입 시그니처로 변형**(D): 지도 범위 밖(D-M3 와 상충).
- **블록 게이트 G2(스캔 open 마다 결정, #318 초안 D-318-08)**: **폐기**(D-323-08). mainblock 안은 읽기 전용 뷰(`REGU_RESOLVED_VALUE`/`RESOLVED`) + 계획된 변환기 + 스코프가 소유하는 실행 임시값뿐이다. 상관 값·비상관 서브쿼리 결과는 스코프 진입 시 계획된 변환기를 1회 적용해 캐시하며(결정 아님), 상관 복합 키는 원소별 strict/keep 쌍과 스캔 스크래치 체인으로 결정·할당 0 을 지킨다.
- **노드 안 union/비팩 flags 비트로 항목을 인라인**(인터페이스 β): 접근자 뒤 구현 변형으로 보류(D-323-16) — #324/#316 측정 뒤 결정.

## Consequences

- `original_domain`/`original_opr_dbtype` 필드와 클론 원복 5곳·PX 스폰 원본 저장 3곳·워커→루트 역전파가 통째로 사라진다(G-02·G-06). 그 자리는 `domain_plan` 포인터가 재사용한다(D-323-13, 구조체 크기 불변 MEM-02). **구현 순서상** 이 필드 제거는 실행 지점이 플랜 도메인에 쓰기를 멈춘 뒤(삭제 티켓 마지막)에만 가능하다 — 그 전에 원복을 지우면 플랜 캐시 클론이 오염된다.
- `pt_make_regu_hostvar` 의 2단계(바인드 값 타입을 도메인으로)와 바인드 피크 재계획의 값 타입 도메인은 삭제된다 — 클라이언트에 숨어 있던 세 번째 결정 지점(D-318-05). 재계획은 값을 비용 추정에만 쓴다.
- 미확정 도메인에 닿으면 전용 오류 `ER_QPROC_DOMAIN_UNRESOLVED = -1382`(로드 경계 (a): `stx_build_domain_plan` 끝, 예외 표 X-1~X-7 정적 배열; 실행 경계 (b): 설치 자리 6곳 = #324 카운터와 1:1) + optdebug assert. `ER_QPROC_INVALID_XASLNODE` 재사용은 기각 — 클라이언트가 그 코드를 받으면 조용히 재컴파일·재실행해 위반을 숨긴다(db_vdb.c:2277, D-318-04, D-323-09). 재컴파일 트리거 목록에 넣지 않는다. 필터/함수 인덱스 스트림은 GATE 비트가 하나라도 있으면 로드 거부, `fpcache_claim` 오류 삼킴은 전파로.
- ~~실행 결정 잔존 X(`median(varchar_col)`·`percentile_* … order by varchar_col`)는 예외 표 X-7 에 RESIDUAL 로 둔다(D-317-15).~~ **Amendment(2026-09-24, #335 D-335-10, 사용자 선택)**: 잔존 X 는 없다 — 게이트가 값을 갖지 않는 문자 인자는 타입으로 정한다(MEDIAN/PERCENTILE 문자 컬럼·식 → 컴파일 DOUBLE, ADDTIME 문자 → 컴파일 VARCHAR, 게이트 의존 문자 식은 해석기가 같은 답), RESIDUAL 표시와 X-7 은 삭제. 답안 변경은 규칙표 §7 D-335-10 행(날짜·시간 문자열 컬럼의 MEDIAN/PERCENTILE → -1118). 결정 원문: [#335 D-335-10](https://github.com/xmilex-git/workspace/issues/335#issuecomment-5797393992).
- 헤더 계약: `domain_resolver.h`(1) ← `domain_plan.h`(2) ← `query_executor.h`(3) ← `fetch.h`(4), `parser/`·`compat/`·`broker/`·`method/` 포함 금지, 순환 검사는 구현 게이트(D-323-15).
- 되돌리는 길: 스트림 레이아웃이 불변이므로 서버 측 변경만 되돌리면 develop 클라이언트·저장된 필터 스트림과 그대로 호환된다. 컴파일 측은 GATE 비트를 내보내지 않으면 VARIABLE 이 로드 경계에 걸리므로, 되돌릴 때는 경계 (a) 를 먼저 끈다.
