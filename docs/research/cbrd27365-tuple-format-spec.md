# CBRD-27365 임시 리스트 튜플 포맷 명세 v0 (prototype)

- 티켓: xmilex-git/workspace #180 (지도 #179). 유형 prototype — 사람이 반응할 초안.
- 대상 소스: `/home/cubrid/dev/cubrid` develop `77bd76bab` (2026-09-02), PostgreSQL `/home/cubrid/dev/postgres` 20devel.
- 스텁: [`cbrd27365-qfile_tuple_layout.h`](cbrd27365-qfile_tuple_layout.h) (컴파일 대상 아님, 명세의 코드 표현).
- 선행 연구: [#183 정렬](cbrd27365-alignment.md), [#184 역방향](cbrd27365-backward-lists.md), [#185 in-place](cbrd27365-inplace-overwrite.md), [#186 정렬레코드·늦은 도메인](cbrd27365-sortrec-and-late-domain.md).
- 이 문서는 **바이트 포맷만** 정한다. 디스크립터 자료구조(#181)와 접근자 API·deform 캐시 구현(#182)은 여기서 요구하는 불변식을 만족하는 한 자유다.

---

## 0. 결정 목록 (D-180-*)

| ID | 결정 | 근거 | 대안/롤백 |
|---|---|---|---|
| D-180-1 | 튜플 헤더 = `len` 4B(네트워크 오더). **bit31 = has-null**, 하위 31비트 = 튜플 전체 길이(패딩 포함). 역방향 가능 리스트만 `prev_len` 4B 추가(플래그 없음, 순수 길이). | 길이는 `int`라 bit31이 오늘도 미사용(항상 양수) → 상한 손실 0. natts/hoff/infomask는 스키마 상수라 불필요(지도 확정). | 별도 1B 플래그 바이트: 정렬 낭비. |
| D-180-2 | 널 비트맵 = has-null일 때만, 헤더 직후, `ceil(type_cnt/8)`B. **1 = bound, 0 = NULL**(PG 동일). 비트 i → `byte[i>>3] & (1<<(i&7))`. `type_cnt` 이후 후행 비트는 0. | PG `att_isnull`/`first_null_attr`를 그대로 옮길 수 있음. 0xFF 바이트 스캔으로 첫 NULL 탐색. | 0=bound 반전: PG 코드 이식 불가, 이점 없음. |
| D-180-3 | `tuple_alignby ∈ {4, 8}` = max(4, 모든 컬럼 alignby) — **리스트 open 시 한 번 계산해 고정**. `DB_TYPE_VARIABLE`(미확정) 컬럼은 8로 계산. 값 영역 시작 `data_off = ALIGN(hdr_size + bitmap_size, tuple_alignby)`; 튜플 길이는 `tuple_alignby` 배수로 반올림. 오프셋 테이블은 **data_off 기준 하나**. | 늦은 도메인 확정(VARIABLE→BIGINT)이 기존 튜플의 `data_off`를 바꾸면 안 됨(§8). PG `t_hoff = MAXALIGN(...)`와 같은 구조. | 오프셋을 튜플 시작 기준으로 두고 data_off 정렬 생략: 헤더 4B 리스트에서 ≤4B 절약되나 has-null 여부별 오프셋 테이블 2개 필요. 성능 티켓에서 재검토 가능. |
| D-180-4 | 고정폭 값은 `alignby`로 자연 정렬(#183 표: SHORT/ENUM 2, INT/FLOAT/DATE/TIME/TIMESTAMP(+LTZ)/TIMESTAMPTZ/DATETIME(+LTZ/TZ)/OID/OBJECT/MONETARY 4, **BIGINT/DOUBLE 8**). 인코딩은 기존 `data_writeval`(네트워크 오더) 그대로. NULL은 0바이트. | #183 결론. 접근자 assert 최대 4 → 무수정 재사용. | 전부 4(힙 관례): `OR_GET_DOUBLE` 캐스트 UB 잔존. alignby 표 한 줄 변경으로 롤백. |
| D-180-5 | 가변 값은 **두 부류**. (a) *byte-packable*(alignby 1): CHAR/VARCHAR/NCHAR/VARNCHAR/BIT/VARBIT/NUMERIC — 정렬 없음, 포맷 길이 헤더 **1B(≤127) / 4B**, 본문은 `index_writeval`/`index_lengthval`/`index_readval`/`index_cmpdisk`. (b) *or-buf*(alignby 4): SET/MULTISET/SEQUENCE/JSON/BLOB/CLOB/(그 외 `index_writeval == NULL`인 가변 타입) — 길이 헤더 위치 `ALIGN4`, 헤더 **항상 4B**, 본문 `data_*`. | (b)는 `or_put_int`(ASSERT_ALIGN 4)로 패킹(§6.2 증거)하므로 비정렬 불가. (a)는 byte/memcpy만 사용(§6.1 증거). PG 패딩바이트 피크 트릭 **미채택**(#183 D-183-2). | 전 가변 타입을 (b)로 통일: 짧은 문자열마다 ≤3B 패딩 + 3B 헤더 낭비. |
| D-180-6 | 가변 길이 헤더 인코딩: 첫 바이트 bit7=0 → 1B, 길이 = byte; bit7=1 → 4B, 길이 = `ntohl(word) & 0x7FFFFFFF`, memcpy로 읽음. 길이는 **본문 바이트 수**(헤더 제외). 0 허용. | 자기 기술, 타입 디스패치 없이 O(1) 스킵. | — |
| D-180-7 | 상수 오프셋 접두 = `min(first_var_col, first_null_attr)` 이전 컬럼. 그 이후는 접두 증분 deform + 튜플 단위 캐시 `(next_col, next_off)`. | 지도 확정. PG `slow` 플래그와 동일 의미. | — |
| D-180-8 | 정렬 레코드 `P_sort_key` 본문 = 키 컬럼만의 **정방향 전용(헤더 4B) 미니 튜플**. 비교자에는 값 본문 포인터(포맷 헤더 건너뜀)를 넘긴다. byte-packable 가변 키의 `sort_f`는 `index_cmpdisk`. | #186. `mr_data_cmpdisk_bit`는 `OR_GET_INT` 캐스트라 정렬 필요(§6.3) → index 변형 필수. | — |
| D-180-9 | 패딩 바이트 내용은 미정의(읽지 않음). 디버그 빌드만 0 채움(valgrind). | 피크 트릭 미채택이라 0 불변식 불필요. | — |

---

## 1. 튜플 전체 구조

```
offset 0
┌──────────────┬──────────────┬──────────────────┬──────┬──────────────────────────────┬─────┐
│ len (4B)     │ prev_len(4B) │ null bitmap      │ pad  │ values (논리 컬럼 순서)        │ pad │
│ bit31=hasnull│ backward만   │ hasnull일 때만    │      │ 고정: ALIGN(alignby) 자연정렬  │     │
│              │              │ ceil(type_cnt/8)B│      │ 가변: [1B|4B hdr][본문]        │     │
└──────────────┴──────────────┴──────────────────┴──────┴──────────────────────────────┴─────┘
                                                  ↑ data_off = ALIGN(hdr_size + bitmap_size, tuple_alignby)
전체 길이 = ALIGN(값 끝, tuple_alignby) = len & 0x7FFFFFFF
```

- `hdr_size` = 4 (forward-only) 또는 8 (backward_capable) — 리스트 단위 상수(#184).
- `bitmap_size` = has-null이면 `(type_cnt + 7) >> 3`, 아니면 0.
- 튜플 시작은 항상 `tuple_alignby` 정렬: 페이지 헤더 32B(`QFILE_PAGE_HEADER_SIZE`) + 모든 튜플 길이가 `tuple_alignby` 배수. 오버플로 튜플은 `qfile_get_tuple`이 `malloc` 버퍼(≥8 정렬)로 조립한 뒤 읽는다.

---

## 2. 헤더

### 2.1 `len` 워드
- `OR_GET_INT(tpl)`로 읽어 `& QFILE_TUPLE_LENGTH_MASK (0x7FFFFFFF)` → 길이. `& 0x80000000` → has-null.
- 기록: `OR_PUT_INT(tpl, len | (has_null ? 0x80000000 : 0))`. 새 튜플의 `len`을 쓰는 곳은 **조립기 한 곳**; 나머지는 튜플 전체 memcpy(플래그 자동 보존).
- 상한: `0x7FFFFFFF`. 오늘 `int tuple_length`의 실질 상한과 같다(음수 길이는 존재하지 않음). `DB_MAX_STRING_LENGTH = 0x3FFFFFFF`인 컬럼 하나 + 헤더는 상한 내.
- **오버플로 튜플**: 첫 조각 헤더에만 `len`(플래그 포함)이 있고, 연속 페이지는 `QFILE_OVERFLOW_TUPLE_PAGE_SIZE`만 가진다(`list_file.c:1530-1560`). 오버플로 판정 `tuple_length > QFILE_MAX_TUPLE_SIZE_IN_PAGE`, 조각 크기 `MIN(len - offset, page_size)`, `qfile_get_tuple`의 `malloc(len)` 등 **38개 읽기 지점 전부 마스킹된 길이**를 써야 한다 → PR-1(#189)에서 `QFILE_GET_TUPLE_LENGTH`를 마스킹 매크로로 바꾸는 것으로 일괄 해결. 페이지 헤더의 `LAST_TUPLE_OFFSET`, `TUPLE_COUNT(-2 = 오버플로 표식)`은 튜플 헤더와 무관.

### 2.2 `prev_len` (backward_capable 리스트만)
- 직전 튜플의 마스킹된 길이. 라이터 `qfile_add_tuple_to_list_id`(`list_file.c:1596`) 단일 지점, 리더 `qfile_scan_prev`/`cursor_prev_tuple` 두 곳(#184). 페이지 첫 튜플은 0(사용 안 함).
- forward-only 리스트에는 필드 자체가 없다. `qfile_scan_prev` 진입 시 `assert(backward_capable)`.

---

## 3. 널 비트맵

- 위치 `hdr_size`, 크기 `(type_cnt+7)>>3`, has-null일 때만 존재. 모든 컬럼(HIDDEN 포함, `type_list` 순서)이 비트 하나를 가진다.
- 비트 의미 1=bound, 0=NULL. 후행 비트(type_cnt..8*bitmap_size-1)는 0으로 기록. 리더는 `first_null_attr` 결과를 `min(res, type_cnt)`로 캡(PG 동일).
- `first_null_attr`: `bitmap_size`바이트를 `!= 0xFF`까지 바이트 스캔 후 `ctz(~byte)`. 비트맵 시작이 4B 정렬만 보장되므로 64B 워드 로드는 하지 않는다(필요하면 memcpy 8B 로드). **64+ 컬럼**은 같은 바이트 루프가 여러 바이트를 도는 것 이상 없음.
- has-null이 아닌 튜플에서는 비트맵 접근 금지(`assert`).

---

## 4. 값 영역 시작과 튜플 길이

- `tuple_alignby = max(4, max_i alignby[i])`, `DB_TYPE_VARIABLE` 컬럼은 8로 계산. **리스트 open 시 고정**(재finalize에서 변경 금지, §8).
- `data_off(has_null) = ALIGN(hdr_size + bitmap_size(has_null), tuple_alignby)` — has-null 여부별 두 값만 존재(디스크립터에 둘 다 저장).
- 컬럼 오프셋 테이블 `off[i]`는 `data_off` 기준, 상수 접두 구간만 유효: `off[0]=0`, `off[i] = ALIGN(off[i-1] + size[i-1], alignby[i])`, 첫 가변 컬럼(및 그 이후)은 `-1`.
- 튜플 길이 = `ALIGN(마지막 값 끝, tuple_alignby)`. 반올림 패딩 ≤ 7B.

---

## 5. 고정폭 값

- 판정: `pr_type::is_size_computed() == false`(#183 §3 표 18종). 크기 `disksize`, 정렬 `alignby`(D-180-4).
- 인코딩: 기존 `data_writeval`/`data_readval`(네트워크 오더). 접근자는 INT 계열은 `OR_GET_INT`, 8B 타입(BIGINT/DOUBLE)은 **memcpy** 로 읽는다(`OR_GET_DOUBLE` 캐스트 UB 제거 기회, 지도 fog 항목 해소).
- NULL = 0바이트(비트맵에만 표시). 따라서 NULL 컬럼 뒤 오프셋은 상수가 아니다(§7).

---

## 6. 가변 값

판정: `pr_type::is_size_computed() == true`. NUMERIC, CHAR(n), BIT(n)도 가변(지도 확정).

### 6.1 부류 (a) byte-packable — alignby 1, 헤더 1B/4B
| 타입 | 라이터 증거(byte/memcpy만) | 리더/비교자 증거 |
|---|---|---|
| CHAR/VARCHAR/NCHAR/VARNCHAR | `pr_write_uncompressed_string_to_buffer` `or_put_byte`+`or_put_data`(`object_primitive.c:14780-14814`); 압축형 `:14703-14747` 길이 두 개도 `OR_PUT_INT(&local)`+`or_put_data` | `or_get_varchar_compression_lengths` `or_get_string_size_byte`+`or_get_data`(`object_representation.h:2134-2170`); `mr_data_cmpdisk_string` `OR_GET_BYTE`/`or_init`(`:11306+`) |
| BIT(n)/VARBIT | `or_put_varbit_internal` `or_put_byte`+`or_put_data`(`object_representation.c:754-782`) | `or_get_varbit_length` → 위와 동일; **`mr_data_cmpdisk_bit`는 `OR_GET_INT(mem)` 캐스트**(`object_primitive.c:13367+`, INT_ALIGNMENT 분기) → 비교자는 **`mr_index_cmpdisk_bit`(memcpy)** 사용 필수 |
| NUMERIC | `mr_data_writeval_numeric` `or_put_data`×2(`:8688-8733`); index 변형은 data 위임 | `mr_data_readval_numeric` `OR_GET_BYTE`(`:8743+`); cmpdisk는 `or_init`→readval→`numeric_db_value_compare` |

- 규칙: 헤더는 직전 값 끝 바로 다음(정렬 없음). 본문 길이 `L = index_lengthval(value)`(CHAR_ALIGNMENT, NUL·패딩 없음). `L ≤ 127` → 1B 헤더 `L`; 아니면 4B 헤더 `htonl(L | 0x80000000)`. 본문 = `index_writeval`. **`data_writeval` 호출 금지**(절대 주소 기준 `or_put_align32` 패딩으로 `lengthval ≠ 기록 크기`, #183 §4.3).
- 본문 안에는 pr_type 자체의 길이 접두(varchar 1B/`0xFF`+8B 등)가 그대로 남는다(이중 접두). O(1) 스킵의 대가로 짧은 문자열은 접두 2B. 인지하고 간다.
- 리더는 `index_readval`, 비교자는 `index_cmpdisk`, 값 포인터는 본문 시작.

### 6.2 부류 (b) or-buf — alignby 4, 헤더 4B 고정
| 타입 | 정렬을 요구하는 증거 |
|---|---|
| SET/MULTISET/SEQUENCE | `or_put_set_header` `or_put_int`(`object_representation.c:3968+`), `or_put_set` `or_put_int`/`or_put_domain`(`:4196+`) — `or_put_int`는 `ASSERT_ALIGN(ptr, INT_ALIGNMENT)`(`object_representation.h:1689`) |
| JSON | `db_json_serialize` → `or_put_int` 다수(`src/compat/db_json.cpp:3511-3638`) |
| BLOB/CLOB (ELO) | `mr_data_writemem_elo` `or_put_bigint`/`or_put_int`/`or_put_string_aligned`(`object_primitive.c` `mr_data_writemem_elo`) |
| `index_writeval == NULL`인 나머지 가변 타입(`tp_Variable`, `tp_Substructure`, `tp_Vobj` 등, `object_primitive.c:1396,1421,1628`) | 리스트 파일에 실제 값으로 나타나지 않음(VARIABLE은 §8). 방어적으로 (b) 처리. |

- 규칙: 헤더 위치 `ALIGN(직전 끝, 4)`, 헤더 4B `htonl(L | 0x80000000)`(1B 축약 없음 — 본문을 4B 정렬에 두기 위해), 본문 `data_writeval`, `L = data_lengthval`. 본문 시작은 4B 정렬이므로 기존 `data_*` 접근자·`or_put_align32` 계약이 오늘과 동일하게 성립(오늘도 값 시작은 8 정렬이지만 `or_*`가 요구하는 것은 4).
- 리더 `data_readval`, 비교자 `data_cmpdisk`.

### 6.3 부류 판정 규칙(디스크립터 finalize 시 한 번)
`is_size_computed() && index_writeval != NULL && 타입 ∈ {CHAR,VARCHAR,NCHAR,VARNCHAR,BIT,VARBIT,NUMERIC}` → (a). 그 외 가변 → (b). 화이트리스트로 고정하는 이유: `index_writeval` 존재만으로는 MIDXKEY 같은 예외를 걸러내지 못하고, 위 표의 "byte/memcpy만" 검증을 타입별로 마친 것이 이 7종이기 때문.

### 6.4 헤더 디코드
```
b0 = *(uint8*)p
if (b0 & 0x80) == 0: hdr=1, L=b0
else:                hdr=4, memcpy(&w, p, 4), L = ntohl(w) & 0x7FFFFFFF
```
비교자·복사 모두 `p + hdr`를 본문으로 본다. 상수 접두가 끝난 뒤 가변 컬럼을 건너뛸 때 이 디코드만 필요(타입 디스패치 없음).

---

## 7. 상수 오프셋 접두와 deform 캐시

- `first_var_col` = 디스크립터 상수(첫 `is_size_computed()` 컬럼, 없으면 `type_cnt`).
- 튜플별 `fast_limit = has_null ? min(first_var_col, first_null_attr(bitmap)) : first_var_col`.
- `i < fast_limit`: 값 위치 `tpl + data_off(has_null) + off[i]`. O(1).
- `i ≥ fast_limit`: 캐시 `(next_col, next_off)`에서 시작해 `next_col..i-1`을 순회. NULL이면 0B, 고정이면 `ALIGN(next_off, alignby)+size`, 가변 (a)이면 헤더 디코드 후 `hdr+L`, (b)이면 `ALIGN4+4+L`. 순회 뒤 캐시 갱신. 캐시는 튜플(스캔 커서) 단위이며 튜플이 바뀌면 `fast_limit`로 리셋.
- 컬럼을 역순으로 접근해도 정확성은 유지(캐시가 앞이면 순회, 뒤면 `fast_limit`부터 재순회).

---

## 8. `DB_TYPE_VARIABLE`과 늦은 도메인 확정

- `qfile_update_domains_on_type_list`(`list_file.c:7063`)는 `DB_TYPE_VARIABLE` 컬럼의 도메인을 확정될 때까지 매 튜플 재시도하며, 확정 전 튜플의 그 컬럼은 반드시 NULL(#186).
- NULL은 0바이트이므로 **컬럼 k의 타입은 k가 NULL인 튜플의 바이트 배치에 영향을 주지 않는다** — 단 `tuple_alignby`·`data_off`는 예외. 그래서 D-180-3: `tuple_alignby`는 open 시 VARIABLE을 8로 쳐서 고정하고 재finalize는 `size/alignby/off/first_var_col`만 갱신한다. 확정 후 기존 튜플을 다시 읽어도 `data_off`가 같으므로 정합.
- 확정 전 VARIABLE 컬럼은 디스크립터에서 "가변 (b)"로 두어 `first_var_col`을 앞당긴다(상수 접두가 짧아지는 비용은 확정 전까지만).
- 조립기가 VARIABLE 컬럼에 non-NULL 값을 받으면 `assert` (기존 `qfile_unify_types` 계약과 동일).

---

## 9. in-place 덮어쓰기 계약 (#185 반영)

- 5지점(orderby_num·inst_num BIGINT 8B, ISLEAF/ISCYCLE INT 4B, parent_pos 44B 상수 → 1B 헤더 44)은 모두 "bound → 동일 인코딩 크기". 접근자 `qfile_tuple_overwrite_fixed(tpl, layout, col, dbval)`가 assert: 값 non-NULL, 기존 열 non-NULL(비트맵), 도메인 타입 일치, `pr_data_writeval_disk_size == size[col]`(가변이면 헤더 디코드 `L`과 일치·헤더 크기 불변).
- 새 포맷에서는 값 헤더가 없으므로 "헤더까지 다시 쓰는" 경로(`qdata_copy_db_value_to_tuple_value`로 orderby_num 재기록)는 구조적으로 사라진다 — 본문 전용 접근자만 존재.

---

## 10. 정렬 레코드 (`P_sort_key`)

- 본문 = 키 컬럼만으로 구성한 **정방향 전용 미니 튜플**(hdr 4B, 비트맵·정렬·가변 규칙 동일, `tuple_alignby`는 키 컬럼 기준으로 별도 계산). `A_sort_key`의 `offset[]`·0=NULL 규약은 유지(#186).
- 비교자 입력: 본문 포인터(고정: 정렬된 위치, 가변 (a): 헤더 뒤 비정렬 → `index_cmpdisk`, 가변 (b): 헤더 뒤 4B 정렬 → `data_cmpdisk`). `qfile_compare_partial_sort_record`의 `PTR_ALIGN(body, MAX_ALIGNMENT)` 는 미니 튜플 시작을 `tuple_alignby`(≤8) 로 맞추는 것으로 대체.

---

## 11. 바이트 배치 예시와 크기표

표기: `F` = forward-only(hdr 4), `B` = backward_capable(hdr 8). 현행 = `8 + Σ(8 + ALIGN8(size))`, NULL은 헤더 8B만(`list_file.c:1926`, `query_opfunc.c:397`).

### (INT, INT) = (7, 9), NULL 없음 — `tuple_alignby 4`
```
F: 00 00 00 0C | 00 00 00 07 | 00 00 00 09            len=12
B: 00 00 00 10 | pp pp pp pp | 00 00 00 07 | 00 00 00 09   len=16
```

### (INT, NULL, BIGINT) = (7, NULL, 5) — `tuple_alignby 8`, has-null, bitmap 1B `0b101 = 0x05`
```
F: 80 00 00 18 | 05 | -- -- --  | 00 00 00 07 | -- -- -- -- | 00 00 00 00 00 00 00 05
   len word(hasnull|24) bitmap  pad→data_off=8  INT@0        pad→ALIGN8     BIGINT@8      total 24
B: 80 00 00 20 | pp pp pp pp | 05 | -- -- -- -- -- -- -- | INT | pad4 | BIGINT     data_off=16, total 32
```
같은 스키마 NULL 없음 (7, 3, 5): F `data_off=4`, INT@0, INT@4, BIGINT@8 → 4+16=20 → **24**; B `data_off=8` → 8+16 = **24**.

### (VARCHAR 'abc', INT) = 본문 `03 61 62 63`(pr_type 접두 1B + 3B) — `tuple_alignby 4`
```
F: 00 00 00 10 | 04 | 03 61 62 63 | -- -- -- | 00 00 00 09        포맷 hdr 1B(L=4), INT는 ALIGN4(5)=8, total 16
```

### (INT, VARCHAR 'abc'): F: INT@0, hdr@4(1B), 본문@5..8 → 9 → ALIGN4 = **12**. B: 8+9=17 → **20**.

### (INT, SET 40B 본문) — 부류 (b): INT@0, SET hdr@ALIGN4(4)=4 (4B), 본문@8..47 → F 4+48 = **52**.

### 크기표 (bytes/tuple)

| 스키마 | 현행 | 새 F | 새 B | 비고 |
|---|---|---|---|---|
| (INT) | 24 | 8 | 12 | |
| (INT, INT) | 40 | 12 | 16 | |
| (BIGINT) | 24 | 16 | 16 | F는 data_off 8로 4B 패딩(D-180-3 비용) |
| (INT, INT, BIGINT) | 56 | 24 | 24 | |
| (INT, NULL, BIGINT) | 48 | 24 | 32 | 비트맵 1B + 정렬 패딩 |
| (VARCHAR 'abc', INT) | 40 | 16 | 20 | 현행: 문자열 `ALIGN8(ALIGN4(3+2))=8`+헤더 8 |
| (INT, VARCHAR 'abc') | 40 | 12 | 20 | |
| (INT, SET 40B) | 72 | 52 | 56 | (b) 4B 헤더 |
| 100×INT, NULL 없음 | 1608 | 404 | 408 | |
| 100×INT, NULL 1개 | 1600 | 416 | 420 | 비트맵 13B → data_off 20(F)/24(B) |
| TPC-H Q1 집계 키+측정 (CHAR(1)×2, DOUBLE×5, BIGINT) | 8+16×2+16×6=136 | 64 | 64 | `tuple_alignby 8` → data_off 8(F/B 동일); CHAR(1)은 가변 (a) 헤더 1B+본문 2B ×2 = 6B, DOUBLE은 ALIGN8(6)=8부터 40B, BIGINT 8B → 56+8 |

---

## 12. 불변식 / assert 목록 (접근자·조립기가 지켜야 할 것)

1. `len & 0x7FFFFFFF ≥ hdr_size`, `len % tuple_alignby == 0`.
2. has-null ⇔ 비트맵에 0비트가 `type_cnt` 안에 존재.
3. 후행 비트맵 비트 == 0.
4. 상수 접두 컬럼 위치 == 증분 deform으로 계산한 위치(디버그에서 교차 검증, PG `first_null_attr`의 slow-path 검증과 같은 방식).
5. 가변 (a): 기록 바이트 수 == `index_lengthval`; `data_writeval` 호출 금지. 가변 (b): 헤더 위치 4B 정렬, 기록 == `data_lengthval`.
6. 고정: 위치 % alignby == 0.
7. `qfile_connect_list`/`qfile_append_list`/`qfile_duplicate_list`: 두 리스트의 `hdr_size`·`tuple_alignby`·`type_cnt` 일치(#184).
8. in-place: §9의 4개 assert.
9. `DB_TYPE_VARIABLE` 컬럼에 non-NULL 조립 시 assert.

---

## 13. 이 티켓이 넘기는 것

- 디스크립터 자료구조·pack/unpack·복제(#181): 여기서 요구하는 필드는 `hdr_size, tuple_alignby, bitmap_size, data_off[2], type_cnt, first_var_col`, 컬럼별 `{kind(fixed|var_a|var_b), size, alignby, off}`. `or_pack_listid`는 변경 불필요(클라이언트가 `type_list`로 재계산, #184).
- 접근자 API·deform 캐시·조립기 시그니처·정렬 레코드 함수 5개(#182). 조립기는 size→fill 2패스(#186).
- 지도 fog 해소: "4B 헤더 뒤 BIGINT 패딩"(D-180-3), "가변 1B 헤더 판별 규칙"(D-180-5/6), "정렬 비교자의 헤더 스킵과 OR 접두 중복"(§6.1 이중 접두 인지, §10), "64+ 컬럼·오버플로 비트맵"(§2.1, §3), "`OR_GET_DOUBLE` UB memcpy 통일"(§5).
- 새로 드러난 사항: `mr_data_cmpdisk_bit`의 `OR_GET_INT` 캐스트 → 가변 (a) 비교자는 `index_cmpdisk` 필수(D-180-8). 가변 타입 두 부류 분리(D-180-5)는 지도 Notes의 "가변은 1B/4B 길이 헤더" 문구를 보정한다(or-buf 부류는 4B 고정).

---

## 14. 검증 추가 (2026-09-02, 사용자 반응에 대한 더블체크)

### 14.1 D-180-3 이 정말 PG 방식인가 → **예**
- `heap_form_minimal_tuple` (`src/backend/access/common/heaptuple.c:1399-1457`): `if (hasnull) len += BITMAPLEN(natts); hoff = len = MAXALIGN(len); /* align user data safely */` → `t_hoff = hoff + MINIMAL_TUPLE_OFFSET`, 값은 `(char*)tuple + hoff`부터. `heap_form_tuple`(`:1033-1101`), `heap_expand_tuple`(`:849, :877`)도 동일 식. 즉 **비트맵 크기를 더한 뒤 한 번 MAXALIGN** — D-180-3의 `data_off = ALIGN(hdr + bitmap, tuple_alignby)`와 같은 구조.
- 오프셋 테이블은 하나: `CompactAttribute.attcacheoff`(`tupdesc.h:70`, "fixed offset into tuple, if known, or -1")는 **`t_hoff` 기준** 상대 오프셋이며 `TupleDescFinalize`(`tupdesc.c:546-555`)가 첫 가변 컬럼 전까지만 채운다. deform은 `tp = tup + t_hoff` 후 `fetch_att(tp + attcacheoff)` (`execTuples.c:1157-1184`: "We can use attcacheoff up until the first NULL … `firstNonCacheOffsetAttr = Min(firstNonCacheOffsetAttr, firstNullAttr)`"). has-null 여부로 테이블을 나누지 않고 `t_hoff`가 흡수한다 — 우리 `data_off[2]`와 동일.
- 차이 하나: PG는 항상 `MAXALIGN`(8). 우리는 `tuple_alignby ∈ {4,8}`로 INT 전용 리스트를 4에 둔다. 튜플 시작이 `tuple_alignby` 정렬(페이지 헤더 32B + 길이 반올림)이므로 상대 정렬 == 절대 정렬이 성립하고, 이 완화는 안전하다. VARIABLE 컬럼을 8로 세어 고정하는 규칙(§8)은 PG에 없는 우리 고유 조건(늦은 도메인 확정) 때문이다.

### 14.2 PG는 JSON을 어떻게 다루나 → **비정렬 저장 + 읽을 때 정렬 사본**
- `jsonb`는 `typlen -1`(varlena), **`typalign 'i'`**, `typstorage 'x'` (`src/include/catalog/pg_type.dat:450-453`; `json`/`text`/`numeric`/`bytea`도 전부 `typalign 'i'`).
- 저장: `heap_fill_tuple`/`fill_val` (`heaptuple.c:355-365`) — `attispackable && VARATT_CAN_MAKE_SHORT(val)`(본문 ≤126B)이면 `SET_VARSIZE_SHORT` 1B 헤더로 **정렬 없이** 기록, 아니면 `att_nominal_alignby(data, attalignby)`로 4B 정렬 후 4B 헤더. 즉 PG도 "같은 컬럼이 튜플마다 정렬/비정렬"이며 그래서 §4.1의 피크 트릭이 필요했다.
- 읽기: `DatumGetJsonbP` = `PG_DETOAST_DATUM` (`src/include/utils/jsonb.h:401-403`) → `detoast_attr` (`src/backend/access/common/detoast.c:175-185`): `VARATT_IS_SHORT`면 **`palloc` + `memcpy`로 4B 헤더 정렬 사본을 만든 뒤** `JsonbContainer`의 `uint32` 필드를 읽는다. 즉 PG는 정렬을 **읽는 쪽에서 복사로 회복**한다.
- CUBRID 대응: `mr_data_readval_json`/`mr_data_cmpdisk_json`은 `db_json_deserialize(buf)`가 `or_get_int` (`src/compat/db_json.cpp:4054-4120`, `ASSERT_ALIGN 4`)를 직접 버퍼에 건다. 선택지는 (i) **(b) 부류로 4B 정렬 위치에 두기(초안 유지)** — 복사 0회, 헤더 3B + 패딩 ≤3B 비용; (ii) PG식 비정렬 저장 + 접근자에서 정렬 스크래치로 memcpy 후 파싱 — JSON은 어차피 파싱으로 힙 문서를 만들므로 복사 1회 추가 비용은 작지만, 접근자에 "타입별 복사 분기"가 생기고 SET/ELO도 같은 처리를 해야 한다. **초안 (i) 유지**를 권고: JSON/SET/ELO는 리스트 파일에서 드물고, 정렬 계약이 오늘과 동일해 회귀 위험이 0이다. (ii)는 성능 티켓(#193)에서 JSON 리스트가 실측 병목일 때만 재검토.

### 14.3 D-180-2/6/8 을 전 타입에 적용해도 현재 코드가 안전한가 → **예, 조건 3개**
pr_type 테이블(`object_primitive.c:897-1763`, NCHAR/VARNCHAR는 `tp_Char`/`tp_String` 별칭 `:1696-1697`) 전수 점검:

| 부류 | 타입 | 새 포맷에서 쓰는 함수 | 정렬 민감 연산 | 판정 |
|---|---|---|---|---|
| FIXED alignby 2 | SHORT, ENUMERATION | `data_*`, `data_cmpdisk` (`OR_GET_SHORT` 캐스트) | 2B 위치 보장 | ✓ |
| FIXED alignby 4 | INT, FLOAT, TIME, TIMESTAMP(+LTZ/TZ), DATE, DATETIME(+LTZ/TZ), MONETARY, OBJECT, OID | `data_*`, `data_cmpdisk` (`OR_GET_INT`/`OR_GET_OID` 캐스트, MONETARY amount는 memcpy) | 4B 위치 보장 | ✓ |
| FIXED alignby 8 | BIGINT, DOUBLE, RESULTSET | `data_*` (BIGINT memcpy, `OR_GET_DOUBLE` 캐스트, RESULTSET `or_put_bigint`) | 8B 위치 보장(힙 4보다 강함) | ✓ |
| VAR (a) alignby 1 | CHAR/NCHAR, VARCHAR/VARNCHAR | `index_writeval/readval/cmpdisk` → `mr_*_string/char_internal(CHAR_ALIGNMENT)`: `or_put_byte`/`or_put_data`, `OR_GET_BYTE`, `or_get_data`; `size=L` 전달 시 `or_advance`/`or_skip_varchar_remainder(…, CHAR_ALIGNMENT)` 패딩 스킵 없음 (`:mr_readval_string_internal`) | 없음 | ✓ |
| VAR (a) | BIT(n) | `mr_index_cmpdisk_bit` → `mr_cmpdisk_bit_internal(CHAR_ALIGNMENT)` **memcpy 분기** (`:13375-13392`) | `data_cmpdisk_bit`(INT_ALIGNMENT)는 `OR_GET_INT(mem)` 캐스트 → **사용 금지** | ✓ (조건 1) |
| VAR (a) | VARBIT | `index_cmpdisk` → `data_cmpdisk_varbit`: `or_init` + `or_get_varbit_length`(byte + `or_get_data`) | 없음 | ✓ |
| VAR (a) | NUMERIC | `index_*` → data 위임: `or_put_data`, `OR_GET_BYTE`, `or_init`→readval→`numeric_db_value_compare` | 없음 | ✓ |
| VAR (b) alignby 4 | SET/MULTISET/SEQUENCE, JSON, ELO/BLOB/CLOB, VARIABLE, SUBSTRUCTURE, VOBJ, MIDXKEY(방어) | `data_*` (`or_put_int`/`or_get_int`/`or_put_bigint` — 모두 `ASSERT_ALIGN 4`) | 4B 위치 보장 — 오늘(8)보다 약하지만 `or_*`가 요구하는 최대는 4(#183 §1.2). `pr_type::alignment 8`(ELO/SUB/VOBJ)은 메모리 표현용이며 디스크 접근자와 무관 | ✓ |
| 제외 | NULL, POINTER, ERROR | disksize 0, 리스트 값으로 출현 불가 | — | 조립기 assert |

**조건 (접근자 API 티켓 #182·PR-2 #190에 넘김):**
1. 정렬 비교자 선택(`list_file.c:4507-4538`의 `sort_f = domain->type->data_cmpdisk`)을 부류별로: (a) → `index_cmpdisk`, 그 외 → `data_cmpdisk`. BIT(n)에서 이 조건을 놓치면 디버그가 아닌 **릴리스에서도** 비정렬 캐스트가 발생한다(x86은 동작, 표준상 UB).
2. (a) 부류의 리더는 `index_readval(buf, val, dom, size=L, …)`로 호출하고 `data_readval`을 부르지 않는다(INT_ALIGNMENT 리더는 NUL+패딩을 건너뛰어 `L`을 넘어 읽음). 클라이언트 `cursor.c:441,489`도 동일 — `pr_type` 테이블은 공용이라 클라이언트 라이브러리에서도 `index_*` 사용 가능.
3. pr_type을 거치지 않고 튜플 값을 직접 캐스트하는 현행 지점(`cursor_get_oid_from_tuple` `(OID*)(tpl+8)` `cursor.c:628`, in-place `OR_PUT_INT(tpl+8)` `list_file.c:1944,1949,2015`, 정렬 레코드 `PTR_ALIGN(…, MAX_ALIGNMENT)` `list_file.c:3538-4256`)은 전부 지도의 19파일 접점 조사에 포함돼 있으며 접근자로 교체된다. 새 포맷에서 남는 직접 캐스트는 접근자 내부 한 곳이어야 한다.

비트맵(D-180-2)과 길이 헤더(D-180-6)는 타입에 독립이다: 헤더 4B 길이 상한 `0x7FFFFFFF` > `DB_MAX_STRING_LENGTH(0x3FFFFFFF)` + pr_type 접두 9B.
