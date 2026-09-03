# CBRD-27365 Design

> 초안(티켓 #188). 최종본은 #194에서 `/cubrid-jira-issue-write`로 `.git_ignored_dir/jira/CBRD-27365/design.md`에
> 생성해 첨부한다. 잠금 근거는 `docs/adr/0016-qfile-tuple-format-pg-style.md`, 상세는 `docs/research/cbrd27365-*.md`.

## 배경

임시 리스트 파일(qfile) 튜플은 값마다 `[flag 4B][len 4B]` 헤더를 붙이고 값을 8B 정렬해 저장한다. 값 하나당 최소
8B 오버헤드 + 패딩이 붙어 `(INT, BIGINT)` 한 행이 40B, TPC-H Q1 집계 행이 136B다. 이 포맷은 자기 기술적이라
`type_list` 없이도 걸을 수 있었지만, 그 대가로 크기와 정렬 I/O를 낭비한다.

PostgreSQL MinimalTuple은 헤더에 has-null 비트와 조건부 널비트맵만 두고 값을 자연 정렬로 이어 붙이며, 컬럼
위치는 스키마(TupleDesc)에서 상수로 캐시한다. 임시 리스트는 스키마(`type_list`)가 리스트별 상수이므로 같은
구조를 더 단순하게 적용할 수 있다.

## 설계 요약

- 튜플 포맷을 `[len 4B(bit31=has-null)] [prev_len 4B, 역방향 가능 리스트만] [널비트맵, has-null시만] [값들: 고정폭은
  4B 이하 자연 정렬, 가변은 비정렬 + 1B/4B 길이 헤더]` 단일 포맷으로 교체하고 구 포맷과 on/off 파라미터를 두지 않는다.
- `type_list`를 레이아웃 디스크립터(컬럼별 off/size/kind/alignby, 리스트별 hdr_size/bitmap_size/data_off)로
  확장하고 도메인을 바꾸는 코드가 같은 자리에서 finalize한다.
- 접근자 API(튜플 슬롯 + 위치/값/일괄 접근자 + 튜플 조립기)를 신설 `src/query/qfile_tuple_layout.h/.c` 한 곳에 두고
  서버·SA·클라이언트(`cursor.c`)가 같은 코드를 쓴다.

## 상세 설계

### 튜플 포맷

| 영역 | 규칙 |
|---|---|
| `len` | 4B 네트워크 오더. bit31 = has-null, 하위 31비트 = 패딩 포함 튜플 길이(4의 배수) |
| `prev_len` | 역방향 가능 리스트(`hdr_size==8`)만. 직전 튜플 길이. 같은 페이지 내 한 칸 후진에만 사용 |
| 널비트맵 | has-null일 때만 헤더 직후 `ceil(type_cnt/8)`B, 비트 1 = bound. NULL 값은 0바이트 |
| 값 시작 | `data_off = ALIGN4(hdr_size + bitmap_size)` |
| 고정폭 | `alignby = min(자연 정렬, 4)`: SHORT/ENUM 2, 나머지 4. BIGINT/DOUBLE도 4, 8B 읽기는 memcpy |
| 가변 | `is_size_computed()` 타입 전부(문자열·BIT·NUMERIC·SET·JSON·ELO). 정렬 없음, 길이 헤더 1B(≤127, bit7=0) / 4B(bit7=1, `ntohl & 0x7FFFFFFF`), 본문은 디스크 표현 |
| 정렬 요구 가변(SET/JSON/ELO) | 포맷은 동일. 접근자가 읽을 때 슬롯 소유 스크래치로 memcpy 후 기존 `data_readval` |
| 패딩 | 내용 미정의(디버그 빌드만 0) |

가변 값 기록은 `index_writeval`/`index_lengthval` 또는 접근자 직접 복사(절대 주소 기준 패딩을 하는
`data_writeval`은 비정렬 위치에 호출 금지). "기록 크기 == 계산 크기" assert.

### 역방향 가능 리스트

`qfile_open_list`의 flag에 backward 비트를 추가하고 `type_list.hdr_size`(4|8)가 유일한 진실이다. 대상: (A)
`XASL_TOP_MOST_XASL` 소유 최종 결과 리스트(CAS scrollable fetch), (B) MERGELIST_PROC outer/inner 자식 리스트,
(C) 분석함수 group/value 리스트 4지점. 정렬 입력의 `qfile_scan_prev` un-read(list_file.c:3633)는 save/jump로
바꿔 forward를 유지한다. `qfile_duplicate_list`는 플래그 상속, copy/clone은 memcpy라 자동 보존. 자식 리스트가
`qfile_copy_list_id`로 결과 리스트로 승격되는 경로(CTE 재귀·hash join·px)에 `hdr_size` 일치 assert.

### 레이아웃 디스크립터 (`QFILE_TUPLE_VALUE_TYPE_LIST` 확장)

```
int type_cnt; uint8 hdr_size; bool finalized; int16 bitmap_size; int16 data_off[2];
int first_non_cached_col; TP_DOMAIN **domp; QFILE_COL_LAYOUT *col;   /* domp와 한 블록 */
QFILE_COL_LAYOUT = { int16 off; int16 size; uint8 kind; uint8 var_access; uint8 alignby; uint8 _pad; }  /* 8B */
```

- `col[]`은 `domp[]`와 한 블록으로 malloc(`qfile_type_list_alloc`), 기존 `free(domp)` 8곳 무수정.
- `qfile_type_list_finalize(tl)`: 순수·멱등. 호출 4곳 — `qfile_open_list` 끝, `qfile_update_domains_on_type_list`
  끝, px `update_domains_on_type_list_by_val_list` 끝, 클라이언트 `or_unpack_unbound_listid` 끝. 복제는 memcpy 상속.
- `first_non_cached_col = min(첫 가변 컬럼, off > 32767인 첫 컬럼)`. 미확정 `DB_TYPE_VARIABLE` 컬럼은 가변으로 계산
  (확정 전 값은 반드시 NULL이므로 재finalize가 기존 튜플 해석을 바꾸지 않음).
- wire: `or_pack_listid`에 int 1개(`hdr_size`) 추가, `or_listid_length` 8→9 int. 디스크립터 본체는 양쪽 재계산.
- 스레드 계약: 디스크립터는 `QFILE_LIST_ID` 소유 스레드만 접근. px XASL_SNAPSHOT 리더는 도메인 구동 순차 deform
  원시 함수 `qfile_tuple_walk_next(walk, dom, &ptr, &len, &is_null)` 사용.
- 디버그: 접근자 진입·finalize 직후 "저장 레이아웃 == domp 재계산" 교차 assert.

### 접근자 API (`src/query/qfile_tuple_layout.h/.c`, cs·sa·cubrid 등록)

- **튜플 슬롯** = 기존 `QFILE_TUPLE_RECORD` 확장: `{char *tpl; int size; const TYPE_LIST *tl; int16 nvalid;
  int16 fast_limit; int32 off; char *scratch; int scratch_size;}`. `tl`은 `qfile_open_list_scan`/`cursor_open`에서
  1회 bind. 튜플 교체는 `qfile_slot_set_tuple` 단일 setter(캐시 리셋: `nvalid=fast_limit`, `off=data_off[has_null]`).
  `fast_limit = has_null ? min(first_non_cached_col, first_null(bitmap)) : first_non_cached_col`.
- **세 층**: 위치 `qfile_slot_locate(rec, col, &len, &is_null) → const char*` / 값 `qfile_slot_read_value(rec, col,
  DB_VALUE*, copy)` (kind/var_access 별 `data_readval`·`index_readval` 분기 내장) / 일괄 `qfile_slot_read_val_list`
  (`qdata_tuple_to_val_list`, method_scan, pl_query_cursor, `cursor_get_tuple_value_list` O(n²)→O(n)).
- **리더 진입점**: `fetch_peek_dbval`/`fetch_copy_dbval`/`fetch_val_list`/`eval_pred`의 `QFILE_TUPLE` 파라미터를
  슬롯 포인터로 교체(~270 호출 지점). `fetch_peek_dbval_pos` 삭제.
- **튜플 조립기**: `qfile_tuple_col_src {const DB_VALUE *val; const char *data; int len; bool is_null;}` 배열 →
  `qfile_tuple_size(tl, src, n, &has_null)` → `qfile_tuple_fill(tl, src, n, out, size)` 2패스, `static inline`.
  size 패스가 본문 길이를 `src[i].len`에 되써 fill이 재계산하지 않음. 4 디스크립터 경로 + `qfile_fast_*` 3 +
  페이지 밖 조립 5곳이 수렴, T_MERGE O(n²)→O(n). `qfile_fast_intint/intval/val_tuple_to_list` 삭제.
- **in-place**: `qfile_slot_overwrite_value(rec, col, val)` — assert(값 non-NULL, 기존 열 non-NULL, 도메인 일치,
  디스크 크기 == 저장 길이), release는 `ER_FAILED`. 대상 5지점: orderby_num 3, inst_num(px), CONNECT BY
  ISLEAF/ISCYCLE/parent_pos.
- **해시조인 선두 키**(고정 오프셋 16 직접 읽기 4벌)·**분석함수 2필드**(`DB_ALIGN(disksize, 8)` stride) → 위치 접근자.

### 정렬 레코드

`P_sort_key` 본문 = 키 컬럼만의 정방향 미니 튜플(hdr 4). `qfile_initialize_sort_key_info`가 `key_tl`을 만들어
`SORTKEY_INFO`에 넣고(읽기 전용 공유) `qfile_compare_partial_sort_record`는 스택 슬롯 2개. 바뀌는 함수 5개:
`qfile_make_sort_key` P분기, `qfile_sort_get_next_parallel` P분기(60줄 복제 → helper 통합),
`qfile_compare_partial_sort_record`, `qfile_compare_with_interpolation_domain`(`(data*, len)` 시그니처),
`qfile_initialize_sort_key_info`. 가변 키 `sort_f`는 `index_cmpdisk`(없으면 스크래치 복사 후 `data_cmpdisk`).
`A_sort_key` `offset[]`·0=NULL 유지, 슬롯 길이는 SORT_REC 전용 `[4B len][data]`. `external_sort.c`는 포맷 무관.

### PR 단계 (개인 fork 브랜치 간, upstream PR은 하나)

1. PR-1a: 슬롯 도입 + fetch 경로 시그니처 교체(기계적, 컴파일러 검증).
2. PR-1b: 매크로 접근 지점을 접근자 호출로 치환(구 포맷 구현체), `qfile_type_list_alloc/finalize`·pack flag,
   `OR_GET_DOUBLE/FLOAT` memcpy, 정렬 입력 un-read save/jump, `fetch_peek_dbval_pos` 삭제. CTP sql 전수.
3. PR-2: 접근자 구현체·조립기 내부를 새 포맷으로 교체, 정렬 레코드, px walk, 구 포맷 삭제. `cursor.c` 전환 포함.

## 대안 검토

- JIRA 원안(all-fixed 리스트 전용 + hidden 파라미터): 접근자마다 포맷 분기 잔존, 테스트 매트릭스 2배, 가변 컬럼
  리스트가 대부분이라 효과 범위 작음 → 기각.
- `tuple_alignby` 8 항상 / 리스트별 `{4,8}`: +4~12B/튜플, 후자는 규칙 3개 + 늦은 도메인 특수 규칙 → 상수 4 채택.
- 가변 값 두 부류(SET 등만 4B 정렬 + 4B 헤더): 포맷 규칙 둘 → 단일 규칙 + 접근자 스크래치 채택.
- `or_buf` 정렬 계약 완화(`OR_GET_INT` memcpy화)로 스크래치 제거: 힙·B-tree 공용 계약 → 범위 밖.
- 역방향 판별을 `QFILE_FLAG_RESULT_FILE`로: "결과 캐시 가능" 표식이라 부적합.
- 첫 정렬키 Datum 호이스팅(PG `SortTuple.datum1`): 정렬 알고리즘 변경 → 별도 이슈.

## 영향 범위

- **컴포넌트**: `query_list.h`, `list_file.c`(37함수), `query_executor.c`(12), `query_hash_join.c`+px(10),
  `cursor.c`(9, 클라이언트), `query_opfunc.c`(8), aggregate/analytic .cpp(4), `query_evaluator.c`(4),
  `network_interface_sr.cpp`(3), `fetch.c`(2), `method_scan.cpp`/`pl_query_cursor.cpp`(2), `object_representation.c`
  (`or_pack_listid`). 총 19파일·약 90함수·약 390 매크로 지점.
- **호환성**: lockstep 업그레이드만 지원. `or_pack_listid` 길이 +4B. 클라이언트/서버 혼합 버전 방어는 하지 않음.
  CAS/JDBC/CCI는 튜플 바이트를 보지 않으므로 드라이버 변경 없음.
- **성능**: `(INT, BIGINT)` 40→16B, TPC-H Q1 집계 행 136→60B. SET/JSON/ELO 컬럼 읽기에만 스크래치 복사 추가.
  판정은 같은 호스트 A/B(TPC-H SF10 parallel=6, 우선 8종 +3%/총합 +2%).
- **알려진 한계**: `off > 32767`인 컬럼부터 상수 오프셋 캐시 포기(고정 컬럼 2700개 이상에서만, 속도만 저하).
  `미정:` 신규 TC 최종 목록(test.md 시점 확정).
