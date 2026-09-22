---
status: proposed
date: 2026-09-22
---
# 바인드 값 변환은 서버 게이트에서 전부 한다 (클라이언트 캐스트 삭제, 값 소유는 XASL_STATE)

클라이언트(CAS·csql·PL)는 바인드 값을 **캐스트 없이 그대로** 보내고(`pt_set_host_variables` 의 `tp_value_cast_preserve_domain` 분기 삭제; 참조 OID 검사와 복제만 유지), 서버 실행 게이트 G1 이 변환 계획에 따라 `val_pos` 마다 값을 바인드 도메인으로 1회 변환한 뒤 게이트 확정 슬롯과 파생 소비자(산술 결과·리스트 컬럼·누산기·정렬 키·비교 도메인·변환기·collation)를 게이트 표에 채운다. 변환된 값은 **XASL_STATE 가 소유하는 별도 배열**에 두고 입력 배열은 `const` 로 남긴다 — SA_MODE 에서 입력 배열은 클라이언트 `parser->host_variables` 그 자체라 제자리 변환은 클라이언트 값을 바꾸고, 결과 캐시 키·tdes 바인드 사본은 원 값 기준이어야 한다. 해제는 만든 스레드가 실행 종료 시에만; 워커는 자기 사본을 자기가 해제한다. 결정 원문: #312 D-M4, #317 D-317-08·10, #318 D-318-03·06, #327 D-327-10.

## Considered Options

- **클라이언트가 게이트 규칙을 흉내 내 미리 변환(이중 변환)**: 기각. 같은 규칙 두 벌(P6), 이전 캠페인의 `host_var_expected_domains[]` OOB → cub_cas SIGSEGV 사고(L-30)의 재현 경로.
- **게이트가 입력 `vd.dbval_ptr[]` 를 제자리 변환**: 기각. SA_MODE 별칭(M4)과 결과 캐시 키 오염, 그리고 연결 스레드가 만든 값을 aptr 를 실행한 PX 워커가 해제해 생긴 교차 mspace free 힙 손상(L-46)의 소유 문제를 다시 연다.
- **한 `?` 의 다중 참조를 "가장 좁은 공통 도메인" 1회 변환으로**: 기각. 등식 축약(`a = ? AND a = b` → `b = ?`)과 UNION 가지 푸시다운이 같은 `val_pos` 를 서로 다른 형제 옆에 복사하므로 참조별 도메인이 실제로 갈린다 — 바인드 값은 `val_pos` 당 1회, 참조별 차이는 **참조별 K 변환기 + 참조별 값 자리**로 풀고, 실패 정책 NULL 은 참조 자리에만 들어가며 공유 원 값은 불변(D-327-10).

## Consequences

- 클라이언트 바인드 캐스트의 **반올림**(DOUBLE/NUMERIC/'1.5' → 2, #319 F-2)이 사라지고 손실 정책은 문맥별 현행으로 게이트 변환기에 붙는다: 산술 인자 strict(-494 또는 파라미터에 따라 NULL), 대입 반올림 -494, 비교 strict-or-keep. -494 는 prepare 뒤 바인드 시점에서 서버 게이트 시점으로 옮겨가고 코드는 같다(P7 ②, L-23 문장 순서 확인).
- `host_var_expected_domains[]` 는 남는다 — prepare 응답의 파라미터 메타, PL/CSQL 보고(`method_callback.cpp`), 바인드 피크 재계획의 입력이다. PL/CSQL 은 선언 타입을 prepare 에 전달한다(S6, PG `param_types` 모델).
- 게이트 뒤 불변식 "값 타입 = 계획 도메인" 이 성립해 `qdata_*_dbval` 값 타입 dispatch·`scan_check_user_given_keylimit_overflow` 같은 계획 신뢰 소비자가 결정적이 된다(L-49). 게이트 확정 결과 컬럼(`SELECT ?`)의 메타는 현행 실행 응답 `include_column_info` 경로로 갱신한다(L-31).
