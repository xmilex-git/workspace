---
status: accepted
date: 2026-09-03
map: xmilex-git/workspace#179 (티켓 #188)
jira: CBRD-27365
---

# 임시 리스트 파일 튜플 포맷을 PG MinimalTuple식 단일 포맷으로 교체한다

임시 리스트 파일(qfile)의 튜플은 오늘 값마다 `[flag 4B][len 4B]` 헤더를 붙이고 값을 8B(`MAX_ALIGNMENT`)로
정렬해 저장한다. `(INT, BIGINT)` 한 행이 40B, TPC-H Q1 집계 행이 136B다. 이것을 PostgreSQL
MinimalTuple과 같은 구조 — `[len(+prev_len)] [has-null 비트] [조건부 널비트맵] [자연정렬 값들, 가변은
1B/4B 길이 헤더]` — 의 **단일 포맷**으로 교체하고(같은 행이 16B, 60B), `type_list`를 레이아웃
디스크립터로 확장하고, 접근자 API를 신설 공용 파일 하나로 모아 서버·SA·클라이언트(`cursor.c`)가 같은
코드를 쓰게 한다. 구 포맷은 삭제하고 on/off 파라미터를 두지 않는다.

이 문서는 설계 단계(연구 티켓 #180~#187)의 결정을 **잠그는 게이트**다. 구현 티켓(#189 PR-1, #190 PR-2,
#191 cursor.c)은 이 문서를 전제로 진행하며, §1의 항목은 구현 중 재논의하지 않는다. 각 항목의 상세·근거·
수치는 `docs/research/cbrd27365-*.md`가 들고 있고 여기서는 인덱스와 핵심 근거만 적는다. 용어는
`CONTEXT.md` "임시 리스트 튜플 포맷" 절을 따른다.

## 1. 잠금 항목 (재논의 금지)

### 1.1 튜플 바이트 포맷 — D-180-1~9 (`cbrd27365-tuple-format-spec.md`)

- **헤더 = `len` 4B(네트워크 오더), bit31 = has-null, 하위 31비트 = 패딩 포함 튜플 길이.** 길이는 `int`라
  bit31이 오늘도 미사용이므로 상한 손실이 없다. natts/hoff/infomask는 스키마 상수라 헤더에 두지 않는다.
- **역방향 가능 리스트만 `prev_len` 4B를 더해 헤더 8B.** 역방향 가능 여부는 리스트 생성 시 선언하는
  리스트 단위 속성이다. 대상은 (A) `XASL_TOP_MOST_XASL`이 소유한 최종 결과 리스트, (B) MERGELIST_PROC
  outer/inner 자식, (C) 분석함수 group/value 리스트 4지점이고 나머지 `qfile_open_list` 호출은 forward-only다
  (#184). 정렬 입력의 `qfile_scan_prev` un-read 한 줄(list_file.c:3633)은 "정렬되는 모든 리스트"를
  backward로 만들므로 save/jump로 바꿔 forward를 유지한다.
- **널 비트맵은 has-null일 때만, 헤더 직후, `ceil(type_cnt/8)`B, 1 = bound.** NULL 값은 0바이트. PG
  `att_isnull`/`first_null_attr`를 그대로 옮긴다.
- **`tuple_alignby = 4` 상수.** `data_off = ALIGN4(hdr + bitmap)`, 튜플 길이는 4의 배수. 고정폭 값의
  `alignby = min(자연 정렬, 4)`: SHORT/ENUM 2, 그 외 4. **BIGINT/DOUBLE도 4이며 8B 읽기는 전부 memcpy**
  (비교자 포함). 근거: CUBRID `or_*`가 assert하는 최대 정렬은 4이고 힙도 BIGINT/DOUBLE을 4B 위치에 저장한다
  (#183). 8을 택할 유일한 이유였던 `OR_GET_DOUBLE` 캐스트 UB는 memcpy로 해소된다. §15 비교에서 항상-4가
  모든 행에서 최소였고 늦은 도메인 확정이 `data_off`를 바꾸지 못하므로 특수 규칙이 사라진다.
- **가변 값은 예외 없는 단일 규칙**: `pr_type::is_size_computed()`인 타입 전부(문자열·BIT·**NUMERIC**·
  SET·JSON·ELO…) — 정렬 없음, 포맷 길이 헤더 1B(≤127B, bit7=0) / 4B(bit7=1, `ntohl & 0x7FFFFFFF`), 본문은
  타입의 디스크 표현. 정렬을 요구하는 타입(`index_readval == NULL`인 SET/JSON/ELO)은 **접근자가 읽을 때
  정렬 스크래치로 복사**한다(PG `detoast_attr` short-header 처리와 동일). 포맷에 타입 예외를 두지 않고
  정렬은 리더 구현의 문제로 둔다. 가변 값 기록은 절대 주소 기준 패딩을 하는 `data_writeval`이 아니라
  `index_*` 계열 또는 접근자 직접 복사로 하고 "기록 크기 == 계산 크기"를 assert한다(#183).
- **상수 오프셋 접두**: 첫 비캐시 컬럼과 이 튜플의 첫 NULL 컬럼 이전까지 위치가 디스크립터 상수. 그 뒤는
  접두 증분 deform + 튜플 단위 캐시.
- **논리 컬럼 순서로 저장**(물리 재배치 없음). 값 바이트 인코딩은 기존 `data_*`(네트워크 오더) 유지 —
  CS 클라이언트가 같은 바이트를 읽고 AIX PPC 빌드 분기가 존재하므로 `index_*` 호스트 오더는 채택하지 않는다.
- **정렬 레코드 `P_sort_key` 본문 = 키 컬럼만의 정방향 미니 튜플**(헤더 4B). 비교자는 접근자를 재사용하고
  가변 키는 `index_cmpdisk`(없으면 스크래치 복사 후 `data_cmpdisk`) — `mr_data_cmpdisk_bit`가 `OR_GET_INT`
  캐스트라 정렬을 요구하기 때문이다. `A_sort_key`의 `offset[]`·0=NULL 규약은 유지한다(#186).
- **패딩 바이트 내용은 미정의.** 피크 트릭을 쓰지 않으므로 0 불변식이 필요 없다(디버그 빌드만 0 채움).

### 1.2 구 포맷 삭제, 파라미터 없음

구 포맷 리더/라이터와 `QFILE_GET_TUPLE_VALUE_*` 계열 매크로 직접 사용은 모두 제거한다. 두 포맷을 병존시키는
런타임 파라미터를 두지 않는다. JIRA 원문은 hidden 파라미터 + all-fixed 리스트 한정이었으나, 두 포맷의
분기가 모든 접근자에 남는 비용과 테스트 매트릭스 2배를 감수할 이유가 없어 **고정/가변 혼합 전체 + 파라미터
없음**으로 확대했다(JIRA 본문은 종착 시 재작성).

### 1.3 `type_list` = 레이아웃 디스크립터 — D-181-1/8/9/10 (`cbrd27365-layout-descriptor.md`)

- **디스크립터 필드는 `QFILE_TUPLE_VALUE_TYPE_LIST`에 추가**하고(별도 heap 객체 아님) 컬럼 배열 `col[]`은
  `domp[]`와 한 블록으로 할당해 `domp`가 블록 선두를 가리킨다 → 기존 `free(domp)` 8곳 무수정. 디스크립터는
  type_list의 결정적 파생물이며 수명이 같다.
- **`hdr_size`(4|8)가 역방향 가능 여부의 유일한 진실.** 별도 bool을 두지 않는다. 같은 사실을 두 필드에
  두면 어긋날 길만 생긴다.
- **wire: `or_pack_listid`에 int 1개(`hdr_size`) 추가**, `or_listid_length` 8→9 int. 디스크립터 본체는
  보내지 않고 양쪽이 재계산한다. `hdr_size`는 도메인에서 파생할 수 없으므로 #180 §13의 "wire 변경 불필요"를
  정정한 결정이다.
- **스레드 계약: 디스크립터는 그 `QFILE_LIST_ID`를 소유한 스레드만 읽고 쓴다.** px XASL_SNAPSHOT 리더는
  디스크립터 대신 도메인 구동 순차 deform 원시 함수를 쓴다. 공유 가변 디스크립터라는 동기화 표면을
  만들지 않는다.
- **mutator-owns-finalize**: `domp`를 바꾸는 코드가 같은 자리에서 `qfile_type_list_finalize`를 부른다.
  복제는 memcpy 상속. 지연 finalize는 채택하지 않는다. (지점 수 정정, #196 D-196-7: 설계 시 4곳으로 셌으나
  구현 조사에서 list_id의 `domp[]`를 직접 바꾸는 지점이 더 있었다 — `qfile_unify_types`, DISTINCT
  집계/분석함수 리스트 도메인 확정 4곳, 해시 GROUP BY 부분 리스트 2곳, RETURN_GENERATED_KEYS 1곳. 규칙은
  그대로이고 PR-1b가 전 지점에 finalize를 넣었으며, `qfile_open_list_scan`의 디버그 교차검증(D-181-7)이
  누락을 잡는다.)

### 1.4 접근자 API — D-182-1/10 (`cbrd27365-accessor-api.md`)

- **새 포맷은 자기 기술적이지 않다** → regu 평가 경로(`fetch_peek_dbval` 155·`fetch_val_list` 51·
  `eval_pred` 47지점)는 raw `QFILE_TUPLE` 대신 **튜플 슬롯**(튜플 + 디스크립터 + deform 캐시)을 받는다.
  `VAL_DESCR` 숨은 채널이나 typedef 의미 변경은 채택하지 않는다 — 한 평가에 리스트가 둘일 때 모호하다.
- 접근자는 위치/값/일괄 세 층이며, 신설 `src/query/qfile_tuple_layout.h/.c` 한 곳에 두고 cs·sa·cubrid 세
  타깃에 등록한다. 서버와 `cursor.c`가 같은 코드를 쓴다.
- **정렬 요구 타입의 스크래치는 슬롯이 소유**한다(지연 확장, 슬롯 소유자가 해제). 비교자는 스택 버퍼 +
  힙 폴백. `or_buf`의 정렬 계약(`OR_GET_INT/SHORT`, `or_get_*`의 `ASSERT_ALIGN`)은 **바꾸지 않는다** —
  힙·B-tree까지 쓰는 라이브러리 계약이라 이 이슈 범위 밖이다(맵 Out of scope).
- 캐시 무효화는 `qfile_slot_set_tuple` 단일 setter(mutator-owns-reset). 포인터 동등성 검사는 두지 않는다 —
  오버플로 버퍼가 같은 포인터에 다른 튜플을 재사용한다.

### 1.5 in-place 덮어쓰기 계약 (#185, `cbrd27365-inplace-overwrite.md`)

리스트 안의 값을 제자리에서 바꾸는 것은 **이미 bound인 값을 같은 인코딩 크기의 값으로** 바꿀 때만 허용된다.
대상 5지점(orderby_num, inst_num(px), CONNECT BY ISLEAF/ISCYCLE/parent_pos) 모두 이 계약이 성립함을
증명했다. orderby_num 재기록은 오늘 값 헤더까지 다시 쓰고 bound 검사가 없으므로 본문 전용 접근자
`qfile_slot_overwrite_value`로 교체하고 assert 4개(값 non-NULL, 기존 열 non-NULL, 도메인 일치, 디스크
크기 == 저장 길이)를 둔다.

### 1.6 호환성: lockstep만, 혼합 버전 방어 없음

CUBRID는 클라이언트/서버 lockstep 업그레이드만 지원한다. 혼합 patch/build 배포 방어
(`net_incompatible_versions[]`)는 넣지 않는다(사용자 결정, 재논의 금지). CAS/JDBC/CCI는 튜플 바이트를 보지
않으므로 리더 측 변경은 `cursor.c`와 서버 바이너리 파일들만이다.

### 1.7 PG와 갈라서는 점과 그 이유

- **헤더에 natts/hoff/infomask 없음.** PG는 힙 튜플과 코드를 공유해야 하고 컬럼 추가(natts 불일치)를
  견뎌야 하지만, 우리 리스트는 스키마가 상수이고 힙과 코드 공유가 없다. has-null은 길이 워드의 bit31로 족하다.
- **역방향은 리스트 단위 플래그(4B/8B 헤더).** PG tuplestore는 backward 플래그를 파일 단위로 갖는 같은
  구조지만 헤더 크기가 아니라 별도 길이 워드다. 우리는 forward-only 리스트가 압도적이라 4B를 아낀다.
- **정렬 상수 4(PG MAXALIGN 8 아님).** `or_*` 계약이 4이고 힙이 4다(§1.1).
- **가변 헤더 판별은 첫 바이트 플래그만**(PG 패딩 바이트 피크 트릭 미채택). 우리 규칙에서는 항상 같은
  분기로 떨어져 죽은 코드와 불변식 2개만 늘린다.
- **슬롯은 `tts_values[]`를 물질화하지 않고 위치만 기억한다.** CUBRID 소비자는 결국 `data_readval`로
  DB_VALUE를 만들어 중간 Datum 배열이 이득이 없다.
- **첫 정렬키 Datum 호이스팅(`SortTuple.datum1`)은 하지 않는다** — 정렬 알고리즘 변경으로 별도 이슈.

## 2. 채택 항목 (구현 중 근거가 있으면 조정 가능)

아래는 포맷 바이트에 영향이 없고 연구 문서에 명시적 되돌림 경로가 있다. 조정하면 이 절에 각주로 남긴다.

| 항목 | 채택안 | 되돌림 경로 |
|---|---|---|
| 컬럼 엔트리 크기 (D-181-3) | 8B `{int16 off,size; uint8 kind,var_access,alignby,_pad}` — PG `CompactAttribute` 선례 | 16B(int32 off); 접근자 코드 불변 |
| 슬롯 타입 (D-182-2) | 기존 `QFILE_TUPLE_RECORD` 확장 | 별도 `QFILE_TUPLE_SLOT` 신설 |
| `qfile_fast_intint/intval/val_tuple_to_list` (D-182-12) | 삭제, 조립기 `static inline` 상수 전파로 대체 | #193 마이크로벤치(고카디널리티 PARTITION BY) 회귀 시 래퍼 복원 |
| `fetch_peek_dbval_pos` (D-182-8) | 삭제 | PR-1b CTP에서 pos 정렬 assert 의존 동작 발견 시 유지 |
| PR 분할 (D-182-17) | PR-1a(슬롯 시그니처, 기계적) → PR-1b(접근자 치환, 포맷 불변) → PR-2(포맷 교체); 개인 fork 브랜치 간 | 1a/1b 합병 |

각주 (구현 중 조정, #189 리뷰·#196):

- **D-189-4 filler-owns-bind (D-182-6 조정)**: "bind는 open 시 1회"를 "레코드를 채우는 스캔이 채울 때마다
  bind"로 바꿨다. `qfile_retrieve_tuple`이 채운 레코드를 `&scan_id->list_id.type_list`에 bind한다(포인터
  스토어 1개). 호출자마다 새로 만드는 지역 레코드(`scan_next_list_scan` 등)에 bind를 맡기면 누락이
  반복된다는 PR-1a 리뷰 지적이 근거. 스캔 밖에서 raw 튜플을 감싸는 스택 슬롯은 여전히 명시 bind.
- **D-196-3 접근자는 디코딩 도메인을 인자로 받는다 (D-182-7 시그니처 조정)**:
  `qfile_slot_read_value (rec, col, dom, v, copy, &is_null)`. 레이아웃은 bind된 디스크립터에서, 디코딩은
  호출자 도메인으로 — 오늘도 fetch는 `pos_descr.dom`, 해시조인은 `fetch_info` 도메인으로 읽으며 리스트
  `domp[col]`과 다를 수 있다(늦은 도메인 확정). NULL 처리도 호출자에게 남긴다(is_null이면 DB_VALUE 불변).
- **D-196-10 일괄 접근자는 별도 API가 아니다 (D-182-7)**: 슬롯 캐시 덕에 순차 `read_value` 루프가 이미
  O(n)이라 `qfile_slot_read_val_list`를 두지 않았다.
- **D-196-5 PR-1b 범위 경계**: PR-1b는 리스트 튜플 *리더*와 in-place 라이터를 접근자로 바꾸고, 복사형
  라이터(merge·정렬키 본문·해시조인 merge)는 접근자로 위치만 얻고 `qfile_legacy_put_value`로 구 헤더를
  다시 쓴다(assembler bridge). 조립기 API(D-182-11)와 정렬 레코드 본문 리더(D-182-14)는 PR-2.

## 3. Considered Options (기각)

- **JIRA 원안: all-fixed 리스트 전용 + hidden 파라미터.** 접근자마다 포맷 분기가 남고 테스트 매트릭스가
  2배다. 가변 컬럼(VARCHAR·NUMERIC)이 있는 리스트가 대부분이라 효과 범위도 작다.
- **`tuple_alignby` 8 항상(PG MAXALIGN) / 리스트별 `{4,8}`.** 각 +4~12B/튜플, 후자는 규칙 3개 + 늦은
  도메인 특수 규칙. 상수 4가 전 항 최소(#180 §15).
- **가변 값 두 부류(SET 등만 4B 정렬 + 4B 고정 헤더).** 복사 0회지만 포맷 규칙이 둘. v0 초안에서 폐기.
- **NULL을 0바이트 대신 고정폭 자리 유지.** 상수 오프셋이 NULL을 넘어 이어지지만 NULL이 많은
  집계·외부조인 리스트에서 크기 이점을 잃고 PG 선례와 갈라진다.
- **역방향 판별을 `QFILE_FLAG_RESULT_FILE`로.** 그 플래그는 "결과 캐시 가능" 표식이라 근거 부적합(#184).
- **디스크립터를 매 접근 시 지연 계산.** hot path에 분기가 생기고 변경 지점이 열거 가능한데 이점이 없다.
- **`or_buf` 정렬 계약 완화로 스크래치 제거.** 힙·B-tree 공용 라이브러리 계약 변경 — 범위 밖.

## 4. Consequences

- **크기**: `(INT, BIGINT)` 40→16B, `(INT, INT)` 40→12B, TPC-H Q1 집계 행 136→60B. 임시 파일 페이지 수와
  정렬 I/O가 그 비율로 준다. 성능 판정은 같은 호스트 A/B(#193, 우선 8종 +3%/총합 +2% 기준).
- **접근 비용**: 상수 접두 컬럼은 O(1), 그 뒤는 접두 증분이라 임의 순서 재접근도 O(1). 8B 값 읽기가 memcpy가
  되지만 컴파일러가 단일 load로 접는다. SET/JSON/ELO 컬럼만 읽을 때 스크래치 복사가 추가된다(리스트에 드묾).
- **코드 접점**: 19파일·약 90함수·약 390 매크로 지점이 접근자 호출로 바뀐다. `fetch_*`/`eval_pred` 시그니처
  변경이 ~270 호출 지점을 건드리므로 PR-1a를 기계적 단계로 분리한다.
- **불변식/assert** (접근자·조립기가 지킨다): `finalized` 진입 assert + 디버그 재계산 교차 검증;
  "기록 크기 == 계산 크기"; `hdr_size==8`은 `qfile_scan_prev`·`cursor_prev_tuple` 두 곳만; connect/append/
  duplicate 및 자식 리스트가 `qfile_copy_list_id`로 결과 리스트로 승격되는 경로(CTE 재귀·hash join·px)의
  `hdr_size` 일치 assert; in-place 4 assert.
- **늦은 도메인 확정**: `DB_TYPE_VARIABLE` 컬럼은 확정될 때까지 매 튜플 재시도되며 확정 전 값은 반드시
  NULL이다. 미확정 컬럼은 가변으로 계산하고 확정 직후 같은 자리에서 재finalize한다. 확정 전 튜플은
  NULL(0바이트)이므로 재finalize로 기존 튜플 해석이 바뀌지 않는다.
- **wire**: `or_pack_listid` 길이 +4B. lockstep 정책이라 자유롭게 바꾸되, 이 변경 이후 구·신 바이너리 혼합은
  assert가 아니라 오독으로 나타날 수 있다 — 방어하지 않기로 한 결정의 대가다(§1.6).
- **범위 밖으로 남긴 관찰**: `qfile_unify_types`의 `assert_release(tuple_cnt==0)`이 "NULL만 든 VARIABLE
  리스트"와 모순(미재현); ordbynum_pos/rownum_col_indices가 HIDDEN regu를 세는 방식과
  `qdata_copy_valptr_list_to_tuple`의 HIDDEN 건너뜀 사이의 잠재 인덱스 어긋남(접근자 도메인 assert로 방어).
