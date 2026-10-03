---
status: accepted
date: 2026-10-03 (2026-09-22 판 #320 과 그 뒤 정정들을 최종 구현 기준으로 다시 씀)
basis: CUBRID/cubrid#8022 HEAD 23a5e5561 (develop 15e7dc8b5 동기화)
locked-by: xmilex-git/workspace#320 (2026-09-22) · #336 D-336-A·B (2026-09-24) · #344 (2026-09-27)
---
# 타입·collation 규칙은 develop 의 것 그대로이고, 옮기는 것은 확정 시점뿐이다 (DOUBLE/VARCHAR 폴백·형제 미러 없음, 답은 승인된 스펙 변경 밖에서 develop 과 같다)

호스트 변수·auto-param·세션변수 읽기·PL 인자(POS)의 도메인과 collation 을 정하는 **규칙**은 develop 의 두 격자 — 클라이언트 파서의 타입 규칙과 서버 실행의 값 타입 규칙(산술·비교 방향·공통값·집계/분석·collation 병합) — 를 그대로 둔다. 바꾸는 것은 **언제** 정하느냐뿐이다.

- **컴파일**은 develop 이 클라이언트에서 캐스트하던 자리(비교·대입의 기대 도메인이 있는 POS)만 고정 도메인으로 싣는다. 그 밖의 POS — 형제가 전부 POS 인 자리, 산술·함수 인자·공통값·집계/분석 인자·UNION/VALUES·TO_CHAR·LIMIT·세션변수 읽기, 숫자 컬럼과 비교하는 `?`, ENUM·ENFORCE collation 자리 — 는 가변 도메인이다: `pt_make_regu_hostvar` 가 `tp_Variable_domain` 을 싣고, 바인드 값의 타입을 도메인으로 쓰던 단계는 없다(D-336-A·B, D-318-05).
- **가변 도메인**은 실행 전 도메인 확정이 바인드 도메인에 develop 의 값 타입 규칙을 실행당 1회 적용해 정한다. 규칙은 서버 전용 모듈 `domain_rules.c` 한 벌이다: `domain_resolve (DOMAIN_CTX, opcode, operands, …)` 가 산술·비교·대입·공통값·집계·분석·함수 인자·리스트 컬럼·키 원소 문맥의 결과 도메인·피연산자 목표 도메인·변환기를 내고, `domain_resolve_comparison` 이 비교를(ADR 0024), `domain_key_rule` 이 인덱스 키 원소의 규칙을 낸다. 값의 내용으로 타입이 갈리는 자리(MEDIAN/PERCENTILE 의 POS, STR_TO_DATE 포맷, ADDTIME 존)는 실행 전 확정이 값을 한 번 보고 타입을 정한 뒤 규칙을 부른다(값에 따른 인자 타입, D-328-06).
- **답은 develop 과 같다**(P0, D-336-A "전부 develop 과 동일 작동, domain 만 실행 전에"). 다른 곳은 사용자가 하나씩 승인한 스펙 변경과 develop 결함이 없어진 자리뿐이다(Consequences).

결정 원문: #317 D-317-01~03·23, #327 D-327-08, #335 D-335-02·10, #336 D-336-A·B, #339 D-339-01, #341 D-341-14, #343 D-343-01, #362 D-362-01, #364 D-364-05, #366 U1~U4, #367 (가)·D-367-07, #374 D-374-16·17. 정본: `docs/research/domain-pin-spec-changes.md`(스펙 변경), `domain-pin-rules-server.md`·`domain-pin-rules-parser.md`(격자), `domain-pin-slot-gate-design.md`(D-336).

## Considered Options

- **문맥 없는 POS 에 DOUBLE/VARCHAR 기본형**(지도 #312 차팅 초안, MySQL 규칙과 동형): 기각. `? + ?` 접합, `enum + ?` 서수/이름, `addtime(?, …)` 오버로드처럼 값 타입으로 갈리는 develop 답이 바뀌고, ENUM 자리의 서수 비교가 조용히 깨진 전례(렛저 L-06: 8행 vs 정답 7행)가 있다. 정확 타입끼리 DOUBLE 로 가는 DB 는 PG·MySQL 에도 없다(#315).
- **형제 미러**(컴파일이 POS 타입을 같은 식의 컬럼·리터럴·CAST 로 확정) + **소비자 도메인 우선**(D-317-04~, D-327-11): 채택했다가 **철회**(D-336-B, 2026-09-24). develop 의 값 의존 답을 바꾼다 — `INSERT … decimal(10,5) VALUES (IFNULL(?, 0))` 의 NUMERIC 값 12.34568 이 미러에서 잘리고, 규칙표 §7 의 답안 변경(정수 형제 산술의 -494, `? + n` 날짜 관용구 65곳, 넓은 바인드 축소, `1.0`→`1`)이 전부 거기서 나왔다. 이전 캠페인의 답 변경 270건도 규칙 변경에서 나왔다(L-01).
- **폭 보존 미러**(형제와 바인드 중 넓은 타입): 기각. 바인드 값이 도메인 계획을 넓히면 계획이 값에 종속된다.
- **늦은 바인딩 식(`abs(?)`)을 바깥 형제로 미러 + CAST**(collation 축의 방식): 타입 축에서 기각(D-327-08). develop 의 "인자 하나라도 MAYBE 면 결과 MAYBE" 답이 바뀐다 — 늦은 바인딩 노드로 두고 실행 전 확정이 생산자 우선으로 1회 푼다.
- **PL/CSQL 선언 타입을 POS 의 형제로**(`host_var_decl_domains[]`): 구현하지 않음(#339). PL 이 보내는 값은 선언 타입과 다르고(CHAR→VARCHAR, TIMESTAMP→DATETIME, NUMERIC→값의 p/s), PL 정적 SQL 의 바인드는 `db_push_values` 로 JDBC 와 같은 클라이언트 캐스트 자리를 지난다 — PL `?` 는 사용자 `?` 와 같은 POS 다.
- **서버 격자를 `object/` 에 두어 클라이언트와 공유**: 기각(D-318-07). 두 격자는 각 한 벌(파서 / 서버)이고 서버 격자는 클라이언트 헤더로 새지 않는다(PHYS-05).

## Consequences

- 승인된 스펙 변경(TC 답 갱신 포함; SQL·develop 답·새 답은 스펙 변경 문서 §1~§10):
  1. 연산자가 받지 않는 타입 조합(-454)과 상수의 계산·변환 실패는 행이 없어도 실행 전 오류다(D-335-02, #367; ADR 0020 의 상수 오류·상수 가지).
  2. 문자 컬럼·식을 받는 MEDIAN/PERCENTILE 은 DOUBLE(날짜 문자열 → -1118), 문자 컬럼을 받는 ADDTIME 은 VARCHAR 다(D-335-10). 값을 갖지 못한 문자 인자를 타입으로 정한 결과이고, 실행 결정 잔존(RESIDUAL)은 없다.
  3. 같은 prepare 를 다시 실행해도 앞 실행의 바인드가 상수를 바꾸지 않는다(#352 — 공유 상수의 제자리 coerce 가 없어졌다).
  4. 리스트 파일을 거친 문자 결과 열의 precision 표시는 최대 길이다(D-338-03).
  5. 집합 연산·CTE 열의 가지 타입이 다르면 행과 무관하게 실행 전 -456 이다(D-341-14; develop 은 두 가지 모두 행이 있을 때만 거부하고 한쪽이 비면 다른 쪽 타입을 썼다).
  6. 행이 고르는 ELT 가지들의 collation 을 병합한다(D-343-01; 합칠 수 없으면 실행 전 -1150).
  7. MEDIAN 과 정렬을 공유하는 분석 함수의 문자 정렬 키는 자기 도메인으로 비교한다(D-362-01).
  8. 공통값 노드의 행 의존 피연산자는 힙 순서와 무관하게 계획 도메인이다(D-364-05).
  9. 문장이 읽는 세션변수는 문장 동안 한 타입이고, 다른 타입은 실행 전 `ER_QPROC_SESSION_VARIABLE_TYPE`(-1384)이다(#366 U1~U4; 세션변수 문장 타입).
  10. 데이터로 닿지 않는 상수는 develop 답이다 — 상수 조건이 막는 가지 아래의 상수 오류는 행이 닿을 때만 낸다(D-367-07). 세션변수 조건은 상수 조건이 아니다(D-368-03).
- develop 결함이 없어지는 자리(§11): 분석 첫 값 변환 실패의 조용한 0행, 정렬 키를 CHAR 로 읽기, optdebug assert 셋(`group_concat(?)` LEAVE, `sum(?) over` 날짜, `? UNION ALL ?` NULL·NULL), ALTER 뒤 옛 타입의 필터 술어(#359), 집계 인자의 함수를 첫 행 전에 한 번 더 부르기.
- 바뀌지 않는 것(§14): 타입 규칙·변환 방향·손실 정책(비교 strict-or-keep, 대입 반올림, `return_null_on_function_errors`), 클라이언트 바인드 캐스트(ADR 0021), collation coercibility·병합·`SET NAMES` 재컴파일, 플랜·결과 캐시 키, 바인드 피크 재계획과 LIKE/LIMIT 재컴파일의 플랜 모양, 인덱스 키의 단일 컬럼 값 그대로·복합 키 strict-or-keep, PL `?` = 사용자 `?`, `hostvar_late_binding` 파라미터(D-344-01: 서버 소비자 0, `?` 를 리터럴로 치환할 뿐), 통계·파라미터 목록.
- 캠페인 밖으로 넘긴 develop 결함(§12): `to_char(col, ?)` 포맷 assert(#363), `enum IN (NULL, NULL)` assert(#353), `enum_col < ?` TIME(#360), `coalesce(enum_col, ?)` collation(#326) — 이 PR 은 건드리지 않는다.
- 되돌리는 길: 스펙 변경 하나를 되돌리는 것은 그 규칙 case 하나(예: 2 는 `domain_rules.c` 의 MEDIAN 문자 인자 case 를 값 분류로)이며, 확정 지점·도메인 계획 구조(ADR 0020)와 무관하다.
