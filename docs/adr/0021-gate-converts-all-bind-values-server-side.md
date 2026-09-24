---
status: accepted (amended 2026-09-23 by #335 D-335-08, 2026-09-24 by #336 D-336-B and 2026-09-24 by #339 — see "Amendment")
date: 2026-09-22
locked-by: xmilex-git/workspace#320 (2026-09-22)
---
# 바인드 값 변환은 서버 게이트에서 전부 한다 (클라이언트 캐스트 삭제, 값 소유는 XASL_STATE, 참조별 자리)

클라이언트(CAS·csql·PL)는 바인드 값을 **캐스트 없이 그대로** 보내고(`pt_set_host_variables` 의 `tp_value_cast_preserve_domain` 분기·CHAR 원 값 유지 분기 삭제; 참조 OID 검사와 복제만 유지), 서버 실행 게이트 G1 이 변환 계획에 따라 `val_pos` 마다 값을 바인드 도메인으로 1회 변환한 뒤 게이트 확정 슬롯과 파생 소비자(산술 결과·리스트 컬럼·누산기·정렬 키·비교 도메인·변환기·collation)를 게이트 표에 채운다. 변환된 값은 **XASL_STATE 가 소유하는 별도 배열**에 두고 입력 배열은 `resolved.in` 으로 `const` 로 남긴다(D-323-03) — SA_MODE 에서 입력 배열은 클라이언트 `parser->host_variables` 그 자체라 제자리 변환은 클라이언트 값을 바꾸고, 서브쿼리 결과 캐시 키·dblink 는 원 값 기준이어야 한다. 게이트 뒤 `vd.dbval_ptr` 는 변환값 배열을 가리키고, 같은 `?` 를 다른 도메인·정책으로 참조하는 regu 는 **참조 자리**를 따로 갖는다(D-323-04). 해제는 만든 스레드가 실행 종료 시에만; 워커는 자기 사본을 자기가 해제한다(ALLOC-08/A64). 결정 원문: #312 D-M4, #317 D-317-08·10, #318 D-318-03·06, #323 D-323-03·04·10·12, #325 D-325-07·08·10·11, #327 D-327-10.

## Amendment (2026-09-23, #335 D-335-08, 사용자 승인)

**바인드 값 캐스트는 클라이언트에 남고, 서버 게이트는 값을 바꾸지 않는다.** 클라이언트는 develop 호출 자리(`pt_set_host_variables`·`do_cast_host_variables_to_expected_domain`, auto-param 은 `pt_make_regu_hostvar` 꼬리 캐스트)에서 develop 규칙 그대로 캐스트하고(`tp_value_cast_preserve_domain` — dpin-03/04 이후 게이트와 같은 셀을 부른다, ADR 0022), 게이트 G1 은 참조마다 값을 복제하고 GATE 슬롯의 도메인만 값에서 기록한다. 이유(#335 2차 게이트):

- **F-335-04 XASL 캐시 공유**: 계획 키는 해시 텍스트의 SHA-1 뿐이고 auto-param 과 사용자 `?` 는 같은 `?:N` 으로 찍혀, 리터럴 문장과 바인드 문장이 계획 하나를 쓴다. 캐스트 결정을 계획에 실으면 어느 형태가 먼저 컴파일했느냐로 답이 갈린다(`bind_misc`, `bug_bts_4966`, `zero_date_format`). 클라이언트는 자기 문장의 기대 도메인을 알므로 문장마다 캐스트하면 캐시와 무관하다.
- **F-335-05 객체 바인드**: CS 모드에서 MOP 는 OID 로 전송되고, OBJECT 목표 변환(클래스 검사·뷰 객체 변환)은 클라이언트 전용 코드다(`tp_value_cast_internal` 의 OBJECT 분기가 `#if !defined (SERVER_MODE)`).

아래 본문의 "클라이언트는 캐스트 없이 그대로 보낸다"·"게이트가 `val_pos` 마다 바인드 도메인으로 변환한다"·Consequences 첫 항목(반올림 소멸·문맥별 손실 정책)은 이 정정으로 대체된다. "클라이언트가 게이트 규칙을 흉내 내 미리 변환" 을 기각한 이유(규칙 두 벌, P6)는 같은 셀을 양쪽이 부르는 지금 구조에는 해당하지 않는다. 값 소유(XASL_STATE)·참조별 자리·해제 규칙은 그대로다. `char(n)_col = ?` 의 VARCHAR 원 값 유지는 `do_cast` 경로에도 적용한다(develop 의 `db_value_domain_init` 이 값을 NULL 로 만들던 B7 결함 소멸, D-327-01). 미러 슬롯(dpin-10)의 변환도 같은 자리(클라이언트, 공유 셀)에서 하되 **모드는 슬롯의 문맥**을 따른다(#336): 대입 자리·CAST 아래·문자 함수 인자는 develop 의 캐스트(대입 셀), 컴파일 미러가 산술·공통값·TO_CHAR·UNION/VALUES 에 붙인 슬롯은 피연산자 셀(strict, 실패는 X1 대로 `return_null_on_function_errors`) — 파서가 슬롯마다 `host_var_convert_modes[]` 로 모드를 적고 `pt_convert_bind_value` 가 그 모드로 부른다. **계획 공유(F-335-04)는 캐시 키로 가른다**(#336 결정 ②): 사용자 `?` 가 하나라도 있는 문장은 해시 텍스트에 `;host_var_cnt=<u>` 를 덧붙여 리터럴 문장과 다른 계획을 쓴다(리터럴만 있는 문장의 키는 develop 과 같다). ENFORCE 플래그 도메인의 바인드 캐스트는 문자 값의 collation 만 바꾸고 타입은 그대로 두므로(`tp_value_cast_internal`), 그런 슬롯의 계획 도메인은 값 타입 = 게이트 슬롯이다(F-336-01).

**정정 2 (2026-09-24, #336 D-336-A·B)**: 컴파일은 슬롯 타입을 만들지 않는다. 컴파일 도메인은 develop 의 클라이언트 캐스트 자리(비교·대입 기대 도메인)뿐이고, 그 밖의 슬롯(산술·함수·공통값·UNION/VALUES·TO_CHAR·LIMIT·세션변수, ENUM·ENFORCE collation 자리)은 GATE 로 게이트가 바인드 값의 도메인을 쓴다 — 미러 슬롯의 OPERAND 변환(위 "미러 슬롯(dpin-10)의 변환도 같은 자리" 문장)은 없다. 규칙표 §7 의 답안 변경은 전부 철회되고 답은 develop 과 같다(`docs/research/domain-pin-slot-gate-design.md`).

**정정 3 (2026-09-24, #339)**: Consequences 셋째 항목의 PL/CSQL 선언 타입 전달(`host_var_decl_domains[]`, 규칙표 S6·D-323-10)은 구현하지 않는다 — 정정 2 가 PL 정적 SQL 의 `?` 에도 그대로 적용된다(PL 인자는 슬롯, 규칙표 S7). PL 이 보내는 값은 선언 타입과 다르다(CHAR → VARCHAR, TIMESTAMP → DATETIME, NUMERIC → 값의 자릿수(p/s), NULL → 타입 없음; `DBType.getObjectDBtype`) — 선언 타입을 슬롯 도메인으로 쓰면 develop 답이 바뀐다. 실행 때 정적 SQL 의 바인드는 `query_handler::set_host_variables` → `db_push_values` 로 JDBC 와 같은 클라이언트 캐스트 자리를 지나므로 PL 전용 경로가 필요 없다. `host_var_expected_domains[]` 는 그대로 남는다.

## Considered Options

- **클라이언트가 게이트 규칙을 흉내 내 미리 변환(이중 변환)**: 기각. 같은 규칙 두 벌(P6), 이전 캠페인의 `host_var_expected_domains[]` OOB → cub_cas SIGSEGV 사고(L-30)의 재현 경로.
- **게이트가 입력 `vd.dbval_ptr[]` 를 제자리 변환**: 기각. SA_MODE 별칭과 결과 캐시 키 오염, 그리고 연결 스레드가 만든 값을 aptr 를 실행한 PX 워커가 해제해 생긴 교차 mspace free 힙 손상(L-46)의 소유 문제를 다시 연다.
- **한 `?` 의 다중 참조를 "가장 좁은 공통 도메인" 1회 변환으로**: 기각. 등식 축약(`a = ? AND a = b` → `b = ?`)과 UNION 가지 푸시다운이 같은 `val_pos` 를 서로 다른 형제 옆에 복사하므로(#323 탐침 P-1·P-2) 참조별 도메인이 실제로 갈린다 — 바인드 값은 `val_pos` 당 1회, 참조별 차이는 참조별 변환기 + 참조별 값 자리로 풀고, 실패 정책 NULL 은 참조 자리에만 들어가며 공유 원 값은 불변.
- **게이트 실패를 일률 -494 또는 일률 NULL 로**: 기각. 실패 정책은 항목마다 문맥별 현행 3종(ERROR / NULL / KEEP; D-323-12, D-327-10).

## Consequences

- 클라이언트 바인드 캐스트의 **반올림**(DOUBLE/NUMERIC/'1.5' → 2, #319 F-2)이 사라지고 손실 정책은 문맥별 현행으로 게이트 변환기에 붙는다: 산술 인자 strict(-494 또는 파라미터에 따라 NULL), 대입·CAST 소비자 반올림(D-325-02), 비교 strict-or-keep. -494 는 prepare 뒤 바인드 시점에서 서버 게이트 시점으로 옮겨가고 코드는 같다(P7 ②). 정수 미러 비교 슬롯(`int_col = ?`)은 오늘 클라이언트 캐스트가 없었으므로(#319 F-1) 게이트 strict-or-keep 이 규칙표 그대로여야 답이 유지된다.
- NULL 원 값은 변환기 밖에서 목표 도메인의 typed NULL 로(D-325-08). 휘발 피연산자(세션변수)의 값은 행마다 읽되 도메인·실패 정책은 게이트 1회, 행 값 타입이 바뀌면 그 행에서만 표 재조회, 비교 문맥 실패는 -494(D-325-10).
- `host_var_expected_domains[]` 는 남는다 — prepare 응답의 파라미터 메타, PL/CSQL 보고(`method_callback.cpp`), 바인드 피크 재계획의 입력이다. PL/CSQL 은 선언 타입을 prepare 요청 배열 `host_var_decl_domains[]` 로 전달하고 파서는 이를 `?` 의 형제로 본다(S6, D-323-10; PG `param_types` 모델). — **정정 3 으로 구현하지 않음**(PL `?` 는 사용자 `?` 와 같은 슬롯).
- 게이트 뒤 불변식 "값 타입 = 계획 도메인 또는 KEEP 기록" 이 성립해 `qdata_*_dbval` 값 타입 dispatch·`scan_check_user_given_keylimit_overflow` 같은 계획 신뢰 소비자가 결정적이 된다(L-49, #325 §7 5). 게이트 확정 결과 컬럼(`SELECT ?`)의 메타는 현행 실행 응답 `include_column_info` 경로로 갱신한다(L-31, wire 변경 0).
- 되돌리는 길: 클라이언트 캐스트 삭제는 `pt_set_host_variables` 한 함수의 두 분기라 독립 커밋으로 되돌릴 수 있다. 되돌리면 게이트가 이미 변환된 값을 받으므로 답은 유지되고 반올림 행(§7)만 develop 답으로 돌아간다.
