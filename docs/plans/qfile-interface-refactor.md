# PR #7866 신규 튜플 코드 명명 정리

상태: 사용자 범위 정정 반영. 기획 중이며 엔진 코드는 수정하지 않았다.
기준 PR: CUBRID/cubrid#7866, SHA 91fc19a83d9d9d5db0d46a137063fe2c8099740d.

## 최종 범위 해석

PR에서 새로 도입하거나 변경한 튜플 코드의 이름과 실제 의미를 맞춘다.
PR 이전부터 있던 리스트·스캔 인터페이스와 기존 타입은 그대로 둔다.
기존 qfile_open_list/close_list/add_tuple_to_list/generate_tuple_into_list/open_list_scan 등은 개명하지 않는다.
QFILE_TUPLE_RECORD/ QFILE_TUPLE_DESCRIPTOR를 SLOT/WRITE_STATE로 일괄 개명하는 제안도 철회한다.
앞선 '일곱 함수 모두 제외' 해석은 사용자 후속 정정으로 대체한다. 새로 도입된 qfile_type_list_finalize는 이번 기획의 핵심 대상이다.

## 핵심 1: SCRATCH가 현재 의미를 설명하지 않는다

사실:
- 현재 QFILE_VAR_SCRATCH는 튜플 안의 본문을 4B 정렬하고 4B 길이 헤더와 data_* 인코딩을 사용한다.
- 과거 임시 정렬 버퍼 복사는 제거됐다. 현재 호출자의 copy 계약에 따라 제자리에서 해석한다.
- 실제 overflow는 페이지를 넘는 큰 튜플의 페이지 체인 처리다. 컬럼 분류와 별개다.
- 사용자 최초 ovf_type 제안의 의도는 복합 타입/구조 해석 특성을 이름에서 드러내는 것. 이후 COMPOSITE를 명시적으로 선택했다. 최근 메시지는 원래 핵심 범위의 재강조로 해석하고 그 선택을 유지한다.

제안:
- QFILE_VAR_SCRATCH → QFILE_VALUE_COMPOSITE.
- 같은 신규 enum군의 QFILE_VAR_DIRECT는 QFILE_VALUE_DIRECT로 접두만 맞추는 최소 변경 후보.
- 신규 var_access 필드는 value_format 후보.
- SCALAR라는 새 의미 분류를 추가하지 않는다.
- 기존 kind의 FIXED/VAR, 실제 타입 판별 조건, 미확정 VARIABLE의 임시 처리, 저장 인코딩·정렬·copy 계약은 그대로 둔다.
- COMPOSITE를 항상 unpack한다거나 실제 overflow로 저장한다는 뜻으로 문서화하지 않는다.

## 핵심 2: 왜 initialize가 아니라 finalize인가

코드가 보여 주는 단계:
1. qfile_type_list_alloc: 메모리와 초기 상태 준비, finalized=false.
2. 도메인 배열 설정.
3. qfile_type_list_finalize: 도메인·헤더로 컬럼 배치와 오프셋을 계산하고 finalized=true.
4. 도메인이 나중에 달라지면 같은 finalize를 다시 호출한다.

finalize라는 이름의 추정 의도는 '입력 도메인을 설정한 뒤 사용할 레이아웃을 완성한다'이다. 작성자 의도 확인으로 단정하지 않는다.
그러나 종료/해제도 아니고 단 한 번의 최종 확정도 아니다. initialize라고 바꾸면 초기 할당·초기화와 반복 가능한 배치 계산을 다시 섞게 된다.

제안:
- qfile_type_list_finalize → qfile_set_layout.
- 신규 finalized 필드 → layout_ready.
- 최초 계산과 도메인 변경 후 재계산 모두 같은 함수를 사용한다.
- 미확정 VARIABLE이 남아 있어도 layout_ready일 수 있으므로 domains_resolved와 구분한다.
- 기존 모듈 수명의 qfile_initialize/qfile_finalize는 변경하지 않는다.
- 기존 list_file.c 등의 호출부는 새 함수·필드 이름 참조만 치환하고 기존 함수 이름이나 동작을 바꾸지 않는다.

## 변경 원칙

- 새 tuple layout 모듈과 PR 신규 분류/필드에서 위 두 문제를 우선 해결한다.
- 그 밖의 이름은 PR diff에 새로 생긴 항목인지 먼저 확인하고, 의미가 실제로 어긋난 경우만 후보로 추가한다.
- 튜플 구조 분리, writer 통합, 새로운 iterator, 중간 버퍼, 래퍼 계층을 도입하지 않는다.
- PEEK/COPY·overflow·버퍼 재사용·페이지 직접 작성·기존 튜플 복사·T_NORMAL/T_COL_SRC 경로 유지.
- 포맷·SQL 결과·인코딩·NULL·오류·소유권·inline 경계 보존.
- 의미 변경은 별도 근거가 있는 항목만 분리 제안. 현재 승인된 의미 변경 없음.

## 검증 계획

- PR base/head diff로 신규 심볼과 기존 심볼을 구분해 변경 목록을 제한한다.
- 선언·정의·참조 이름만 기계적으로 치환하고 역치환 diff로 로직 불변을 확인한다.
- server/SA/client 공용 코드의 기존 빌드로 이름 누락을 확인한다. 실행은 저장소 위임 규칙을 따른다.
- 로직 변경이 없다면 rename을 반복 검증하는 신규 테스트·불필요한 성능 캠페인을 추가하지 않는다.
- 동작 변경이 필요해지면 해당 회귀 사례와 측정을 별도로 계획한다.

## 남은 확인

qfile_set_layout은 사용자 확정 이름이다. QFILE_VALUE_COMPOSITE의 정확한 심볼과 layout_ready는 아직 후보이다.
COMPOSITE는 사용자 선택이며 정확한 C 심볼은 제안 단계다.
전체 호출 인터페이스 재설계 인터뷰는 중단하고 이 두 핵심에 대한 이름·의미 합의로 기획을 마무리한다.

## 근거

- [PR](https://github.com/CUBRID/cubrid/pull/7866)
- [타입별 레이아웃 분류](https://github.com/CUBRID/cubrid/blob/91fc19a83d9d9d5db0d46a137063fe2c8099740d/src/query/qfile_tuple_layout.h#L40)
- [할당과 레이아웃 계산](https://github.com/CUBRID/cubrid/blob/91fc19a83d9d9d5db0d46a137063fe2c8099740d/src/query/qfile_tuple_layout.c#L86)


## 추가 합의와 읽기 이름 정리

사용자는 qfile_type_list_finalize의 대체명으로 qfile_set_layout(type_list)를 선택했다.
이 함수는 type_list의 도메인에서 레이아웃을 계산해 그 객체에 저장한다. 초기 할당이나 해제 함수가 아니며 반복 호출 가능하다.

사용자는 새 튜플 코드의 tl/tpl/bind 같은 축약과 추상적 동사가 읽기 어렵다고 지적했다.
새 모듈의 매개변수와 지역 변수 및 PR 신규 필드에 대해 아래 후보를 검토한다. 확정된 항목만 구현 대상으로 삼는다.
PR 이전 필드 tpl을 저장소 전체에서 바꾸는 작업은 포함하지 않는다. 기존 필드에 접근하더라도 새 지역 변수는 tuple_ptr처럼 풀어 쓴다.

| 현재 | 후보 | 정확한 의미 |
|---|---|---|
| tl | type_list | 컬럼 도메인과 계산된 레이아웃을 가진 타입 목록 |
| tpl | tuple_ptr | 튜플 전체 바이트의 시작 주소. DB_VALUE 배열이 아님 |
| rec | tuple_slot | 현재 튜플 바이트·타입 목록·컬럼 탐색 상태를 묶은 읽기 상태 |
| col (정수) | column_index | 읽을 컬럼 번호 |
| c 또는 col (컬럼 배치 포인터) | column_layout | 해당 컬럼의 배치 규칙. column_index와 구분 |
| body | column_data | 길이 헤더를 제외한 컬럼 저장 본문 |
| len (본문 길이) | column_data_size | 컬럼 본문 바이트 수. 튜플 전체 길이와 구분 |
| qfile_slot_bind | qfile_slot_set_layout | type_list의 레이아웃을 읽기에 사용하도록 포인터 연결. 레이아웃 계산·복사·소유권 이전 아님 |
| qfile_slot_set_tuple | qfile_slot_set_tuple_ptr | 읽을 튜플 바이트 포인터 교체와 위치 캐시 초기화. 저장 바이트 작성/복사 아님 |
| qfile_slot_fill | qfile_slot_set_tuple_ptr_and_layout | 튜플 바이트와 type_list를 함께 연결. 바이트 fill과 구분 |
| qfile_slot_locate | qfile_slot_get_column_data | 컬럼 번호로 저장 본문의 주소를 찾고 본문 크기·NULL 여부 반환. DB_VALUE 해석 아님 |
| qfile_slot_read_value | qfile_slot_read_column_value | 저장 본문을 호출자 도메인으로 해석. 기존 copy·NULL·오류 계약 유지 |

위 함수명은 제안이며 아직 최종 채택 전이다.
qfile_slot_get_column_data의 내부 walk helper는 같은 어근으로 맞추되 inline/out-of-line 경계와 탐색 알고리즘은 그대로 둔다.
type_list를 통해 공통 배치를 참조하는 것과 qfile_set_layout으로 그 배치를 계산하는 것은 구별한다.

호출 예시 (제안 이름, 기존 인자 순서/시그니처 의미 유지):

    qfile_set_layout (type_list);
    qfile_slot_set_layout (tuple_slot, type_list);
    qfile_slot_set_tuple_ptr (tuple_slot, tuple_ptr);
    column_data = qfile_slot_get_column_data (
        tuple_slot, column_index, &column_data_size, &is_null);

첫 줄은 리스트 도메인 설정/변경 지점의 내부 작업이며 매 행 수행하지 않는다.
두 포인터 설정은 raw tuple을 스캔 밖에서 감싸는 전문 경로의 예시다.
일반 scan은 현재도 qfile_retrieve_tuple에서 layout과 tuple을 함께 채워 주므로 호출자가 매번 수동 연결하도록 바꾸지 않는다.
포인터 설정은 캐시를 초기화하며 메모리 할당·튜플 복사를 추가하지 않는다.
NULL 결과에서는 column_data를 데이터 본문처럼 읽지 않고 is_null을 먼저 확인한다.


## tuple_ptr 및 슬롯 탐색 이름 확정

새 튜플 코드의 바이트 포인터 이름은 tuple_ptr.
관련 후보도 qfile_slot_set_tuple_ptr / qfile_slot_set_tuple_ptr_and_layout으로 맞춘다.
기존 tpl 필드의 저장소 전역 개명은 하지 않는다.

사용자가 선택한 슬롯 탐색 이름:

| 현재 | 확정 이름 | 계약 |
|---|---|---|
| nvalid | cached_column_index_in_tuple | 캐시에 저장한 탐색 위치의 컬럼 번호. -1이면 초기화 전. 디코딩 완료 값 개수가 아님 |
| off (슬롯 필드) | cached_byte_offset_in_tuple | 해당 컬럼 탐색을 시작할 튜플 시작 기준 바이트 위치. 컬럼 정렬 적용 전일 수 있음 |
| fast_limit | fixed_length_col_cnt | 이 튜플에서 상수 오프셋으로 바로 접근 가능한 선두 컬럼 수. 전체 고정폭 컬럼 개수가 아님 |
| data_off (슬롯 필드) | data_off 유지 | 헤더·조건부 비트맵·시작 패딩 뒤의 값 영역 시작 위치 |
| qfile_slot_start | qfile_slot_start 유지 | 현재 튜플의 컬럼 탐색 캐시 초기화 |

fixed_length_col_cnt는 첫 가변 컬럼·상수 오프셋 표현 한계·이 튜플의 첫 NULL 등에 의해 제한된다.
예를 들어 (INT, VARCHAR, BIGINT)는 고정폭 컬럼이 둘이지만 직접 접근 가능한 접두부는 INT까지다.
주석에 이 차이를 명시한다. 이름을 바꾼다고 계산 조건을 전체 고정폭 컬럼 개수로 바꾸지 않는다.
컬럼 레이아웃의 off는 값 영역 기준 상대 오프셋이므로 슬롯 off와 무차별 치환하지 않는다.
타입 목록 data_off[2]도 그대로 둔다.

## 추가 충돌 후보 승인 절차

사용자 요청: 확정 이름과 충돌하는 PR 신규·변경 이름을 조사하고, 현재 이름·충돌 이유·후보 이름·PR 근거를 먼저 제시한다. 사용자 확인을 받은 항목만 본 기획의 확정 목록에 추가한다. 조사 중 발견한 추가 후보는 승인 전에는 확정하거나 이 문서에 추가하지 않는다. 기존 미승인 후보도 확정 이름과 구분한다.


## 추가 충돌 후보 확정

사용자 승인: 후보 1–5 전부 채택. 후보 4의 column_layouts만 column_layout_array로 수정한다.
엔진 구현은 아직 하지 않으며 아래를 기획의 확정 변경 목록에 추가한다.

| 대상 | 현재 | 확정 이름 |
|---|---|---|
| QFILE_TUPLE_WALK | col | next_column_index_in_tuple |
| QFILE_TUPLE_WALK | off | next_byte_offset_in_tuple |
| QFILE_COL_LAYOUT | off | byte_offset_in_values |
| QFILE_TUPLE_VALUE_TYPE_LIST | col | column_layout_array |
| QFILE_TUPLE_VALUE_TYPE_LIST | first_non_cached_col | max_fixed_length_col_cnt |

의미 보존:
- next_*는 순차 탐색기의 다음 읽기 위치다. 슬롯의 cached_*와 구분한다.
- next_byte_offset_in_tuple은 정렬 적용 전일 수 있으며 튜플 시작 기준이다.
- byte_offset_in_values는 data_off부터의 상대 위치다. -1 sentinel과 상수 오프셋 유효 범위를 그대로 둔다.
- column_layout_array는 배열, column_layout은 단일 컬럼 배치 포인터로 구분한다.
- max_fixed_length_col_cnt는 타입 목록에서 계산한 NULL 미반영 상한이다. 현재 튜플의 첫 NULL 등을 반영한 fixed_length_col_cnt와 다르며, 전체 고정폭 컬럼 개수로 계산하지 않는다.
- cached_column_index_in_tuple의 기존 'columns deformed so far' 주석은 캐시된 탐색 위치의 컬럼 번호이며 -1이면 초기화 전이라고 정정한다.
- 이번 승인으로 변경한 이름은 위 다섯 항목이다. 앞서 제시된 다른 미승인 후보를 함께 승인한 것으로 해석하지 않는다.

근거: PR 91fc19a83, qfile_tuple_layout.h:873 및 query_list.h:312–345.
독립 조사 보고서: .git_ignored_dir/scratch/herdr-integration/qfile-name-audit-1788862309/report.md.
