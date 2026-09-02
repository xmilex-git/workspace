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
| D-180-3 | **`tuple_alignby = 4` 상수**(2026-09-02 사용자 결정, §15 C안). 값 영역 시작 `data_off = ALIGN4(hdr_size + bitmap_size)`; 튜플 길이는 4의 배수로 반올림. 오프셋 테이블은 **data_off 기준 하나**(PG `t_hoff` + `attcacheoff`와 같은 구조, §14.1). | 규칙 1개. 힙 관례(`DB_ATT_ALIGN`=4)와 일치. 늦은 도메인 확정이 `data_off`를 바꿀 수 없어 §8 특수 규칙 불필요. §15 압축표에서 전 항 최소. | A 항상 8(PG MAXALIGN): +4~12B/튜플. B 리스트별 `{4,8}`+open 고정: 규칙 3개, 8B 컬럼 없는 리스트에서만 A보다 유리. 상수 한 줄로 전환 가능. |
| D-180-4 | 고정폭 값의 `alignby` = **min(자연 정렬, 4)**: SHORT/ENUM 2, 그 외 전부 4 (**BIGINT/DOUBLE/RESULTSET도 4** — #183 D-183-1의 "8" 권고는 롤백 경로대로 4로 조정). 인코딩은 기존 `data_writeval`(네트워크 오더) 그대로. **8B 값 읽기는 memcpy**(SER-03) — 접근자·비교자 모두. NULL은 0바이트. | #183 §1.2: CUBRID `or_*`가 assert하는 최대 정렬은 4, 힙도 BIGINT/DOUBLE을 4B에 저장. 8을 택한 유일한 이유였던 `OR_GET_DOUBLE` 캐스트 UB는 memcpy로 해소(§15.4). | 8로 되돌리기: alignby 표 + `tuple_alignby` 상수 변경. |
| D-180-5 | 가변 값은 **단일 규칙**(예외 없음, 2026-09-02 사용자 결정으로 v0 초안의 두 부류 폐기): `is_size_computed()` 타입 전부 — 정렬 없음(직전 값 끝 = 헤더 시작), 포맷 길이 헤더 **1B(≤127) / 4B**, 본문 = 타입의 디스크 표현(패딩 없음). 정렬을 요구하는 타입(SET/JSON/BLOB/CLOB 등 `or_put_int` 계열로 패킹, `index_readval == NULL`)은 **접근자가 읽을 때 정렬 스크래치로 memcpy 후 기존 `data_*` 호출**(PG `detoast_attr`의 short-header 처리와 동일, §14.2). 문자열/BIT/NUMERIC은 복사 없이 `index_*` 직접. | 포맷에 타입 예외를 두지 않는다. 정렬은 리더 구현의 문제이며 PG도 그렇게 푼다. 복사 비용은 리스트에 드문 타입에만 발생. | v0 초안(SET 등만 4B 정렬 + 4B 고정 헤더): 복사 0회지만 포맷 규칙이 둘. 롤백은 접근자의 복사 분기를 정렬 저장으로 바꾸는 것(포맷 변경 필요). |
| D-180-6 | 가변 길이 헤더 인코딩: 첫 바이트 bit7=0 → 1B, 길이 = byte; bit7=1 → 4B, 길이 = `ntohl(word) & 0x7FFFFFFF`, memcpy로 읽음. 길이는 **본문 바이트 수**(헤더 제외). 0 허용. | 자기 기술, 타입 디스패치 없이 O(1) 스킵. | — |
| D-180-7 | 상수 오프셋 접두 = `min(first_var_col, first_null_attr)` 이전 컬럼. 그 이후는 접두 증분 deform + 튜플 단위 캐시 `(next_col, next_off)`. | 지도 확정. PG `slow` 플래그와 동일 의미. | — |
| D-180-8 | 정렬 레코드 `P_sort_key` 본문 = 키 컬럼만의 **정방향 전용(헤더 4B) 미니 튜플**. 비교자에는 값 본문 포인터(포맷 헤더 건너뜀)를 넘긴다. 가변 키의 `sort_f`는 `index_cmpdisk`가 있으면 그것, 없으면 정렬 스크래치 복사 후 `data_cmpdisk`. | #186. `mr_data_cmpdisk_bit`는 `OR_GET_INT` 캐스트라 정렬 필요(§6.3) → index 변형 필수. | — |
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
                                                  ↑ data_off = ALIGN4(hdr_size + bitmap_size)
전체 길이 = ALIGN4(값 끝) = len & 0x7FFFFFFF
```

- `hdr_size` = 4 (forward-only) 또는 8 (backward_capable) — 리스트 단위 상수(#184).
- `bitmap_size` = has-null이면 `(type_cnt + 7) >> 3`, 아니면 0.
- 튜플 시작은 항상 4B 정렬: 페이지 헤더 32B(`QFILE_PAGE_HEADER_SIZE`) + 모든 튜플 길이가 4의 배수. 오버플로 튜플은 `qfile_get_tuple`이 `malloc` 버퍼(≥8 정렬)로 조립한 뒤 읽는다.

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

- `tuple_alignby = 4` 상수(D-180-3). 컬럼 `alignby ≤ 4`이므로 튜플 시작 4B 정렬만으로 모든 고정 값의 정렬이 성립한다.
- `data_off(has_null) = ALIGN4(hdr_size + bitmap_size(has_null))` — has-null 여부별 두 값만 존재(디스크립터에 둘 다 저장). 비트맵 ≤ 4B(≤32 컬럼)인 forward 리스트는 `data_off` = 8, backward는 12.
- 컬럼 오프셋 테이블 `off[i]`는 `data_off` 기준, 상수 접두 구간만 유효: `off[0]=0`, `off[i] = ALIGN(off[i-1] + size[i-1], alignby[i])`, 첫 가변 컬럼(및 그 이후)은 `-1`.
- 튜플 길이 = `ALIGN4(마지막 값 끝)`. 반올림 패딩 ≤ 3B.

---

## 5. 고정폭 값

- 판정: `pr_type::is_size_computed() == false`(#183 §3 표 18종). 크기 `disksize`, 정렬 `alignby ∈ {2,4}`(D-180-4).
- 인코딩: 기존 `data_writeval`/`data_readval`(네트워크 오더). 접근자는 2B/4B 필드는 `OR_GET_SHORT/INT`, 8B 타입(BIGINT/DOUBLE, MONETARY amount)은 **memcpy**로 읽는다. 정렬 비교자 경로가 쓰는 `OR_GET_DOUBLE`/`OR_GET_FLOAT` 캐스트(`object_representation.h:164`)는 PR-1에서 memcpy로 수정(PUT은 이미 memcpy) — 힙의 4B DOUBLE 잠재 UB도 함께 정리.
- NULL = 0바이트(비트맵에만 표시). 따라서 NULL 컬럼 뒤 오프셋은 상수가 아니다(§7).

---

## 6. 가변 값 (단일 규칙)

판정: `pr_type::is_size_computed() == true`. NUMERIC, CHAR(n), BIT(n)도 가변(지도 확정). **모든 가변 타입에 같은 저장 규칙**을 적용한다.

### 6.1 저장 규칙
- 헤더는 직전 값 끝 바로 다음(정렬 없음). 본문 길이 `L` = 패딩 없는 디스크 길이(§6.3). `L ≤ 127` → 1B 헤더 `L`; 아니면 4B 헤더 `htonl(L | 0x80000000)`. 본문 = 타입의 디스크 표현 그대로, 뒤 패딩 없음.
- 본문 안에는 pr_type 자체의 길이 접두(varchar 1B/`0xFF`+8B 등)가 그대로 남는다(이중 접두). O(1) 스킵의 대가로 짧은 문자열은 접두 2B. 인지하고 간다.
- 리더·비교자·복사 모두 `p + hdr`를 본문으로 본다(§6.4).

### 6.2 타입별 접근 방식 — 포맷이 아닌 **접근자 구현**의 분기
| 타입 | 라이터 | 리더 / 비교자 | 근거 |
|---|---|---|---|
| CHAR/NCHAR/VARCHAR/VARNCHAR | `index_writeval` (`mr_writeval_string_internal(CHAR_ALIGNMENT)`: `or_put_byte`+`or_put_data`, `object_primitive.c:14703-14814`) | `index_readval(size=L)` / `index_cmpdisk` — `OR_GET_BYTE`, `or_get_data`만 사용(`object_representation.h:2134-2170`, `object_primitive.c:11298+`) | 비정렬 직접 접근 안전 |
| BIT(n)/VARBIT | `index_writeval` (`or_put_varbit_internal` byte+data, `object_representation.c:754-782`) | `index_readval` / **`index_cmpdisk`**(`mr_cmpdisk_bit_internal(CHAR_ALIGNMENT)` memcpy 분기 `:13375-13392`). `data_cmpdisk_bit`는 `OR_GET_INT` 캐스트 → 금지 | 〃 |
| NUMERIC | `index_writeval`(= data, `or_put_data`×2 `:8688-8733`) | `index_readval` / `index_cmpdisk` (`OR_GET_BYTE`, `or_init`) | 〃 |
| SET/MULTISET/SEQUENCE, JSON, BLOB/CLOB/ELO, VARIABLE, SUBSTRUCTURE, VOBJ, MIDXKEY(방어) — `index_readval == NULL` | `data_writeval`을 **정렬 스크래치**에 기록 후 튜플로 memcpy (`or_put_int` `ASSERT_ALIGN 4`, `object_representation.c:3968+`, `db_json.cpp:3511-3638`) | 본문 `L`바이트를 정렬 스크래치로 memcpy 후 `data_readval`/`data_cmpdisk` (PG `detoast_attr` `VARATT_IS_SHORT` 분기와 동일, `detoast.c:175-185`) | 기존 함수 무수정. 복사 1회(L바이트) — 이 타입들은 리스트에 드물고, JSON/SET readval은 어차피 힙 객체를 만든다 |

분기 기준은 pr_type 능력(`index_readval != NULL`) 하나이며 화이트리스트가 아니다. 스크래치는 스레드 로컬 재사용 버퍼(ALLOC 규칙: 튜플마다 malloc 금지), `L`이 상한을 넘으면 1회 확장.

### 6.3 길이 계산 — "기록 == 계산" 불변식
- `index_readval` 있는 타입: `L = index_lengthval(value)` (CHAR_ALIGNMENT: NUL·패딩 없음). **`data_writeval`/`data_lengthval` 호출 금지** — 문자열 `data_writeval`은 절대 주소 기준 `or_put_align32` 패딩으로 `lengthval ≠ 기록 크기`(#183 §4.3).
- 그 외: `L = data_lengthval(value)`; 스크래치에 `data_writeval` 후 `buf.ptr - buf.buffer == L` assert.

### 6.4 헤더 디코드
```
b0 = *(uint8*)p
if (b0 & 0x80) == 0: hdr=1, L=b0
else:                hdr=4, memcpy(&w, p, 4), L = ntohl(w) & 0x7FFFFFFF
```
상수 접두가 끝난 뒤 가변 컬럼을 건너뛸 때 이 디코드만 필요(타입 디스패치 없음). 상한 `0x7FFFFFFF` > `DB_MAX_STRING_LENGTH(0x3FFFFFFF)` + pr_type 접두 9B.

---

## 7. 상수 오프셋 접두와 deform 캐시

- `first_var_col` = 디스크립터 상수(첫 `is_size_computed()` 컬럼, 없으면 `type_cnt`).
- 튜플별 `fast_limit = has_null ? min(first_var_col, first_null_attr(bitmap)) : first_var_col`.
- `i < fast_limit`: 값 위치 `tpl + data_off(has_null) + off[i]`. O(1).
- `i ≥ fast_limit`: 캐시 `(next_col, next_off)`에서 시작해 `next_col..i-1`을 순회. NULL이면 0B, 고정이면 `ALIGN(next_off, alignby)+size`, 가변이면 헤더 디코드 후 `hdr+L`. 순회 뒤 캐시 갱신. 캐시는 튜플(스캔 커서) 단위이며 튜플이 바뀌면 `fast_limit`로 리셋.
- 컬럼을 역순으로 접근해도 정확성은 유지(캐시가 앞이면 순회, 뒤면 `fast_limit`부터 재순회).

---

## 8. `DB_TYPE_VARIABLE`과 늦은 도메인 확정

- `qfile_update_domains_on_type_list`(`list_file.c:7063`)는 `DB_TYPE_VARIABLE` 컬럼의 도메인을 확정될 때까지 매 튜플 재시도하며, 확정 전 튜플의 그 컬럼은 반드시 NULL(#186).
- NULL은 0바이트이므로 **컬럼 k의 타입은 k가 NULL인 튜플의 바이트 배치에 영향을 주지 않는다.** `tuple_alignby`가 상수 4(D-180-3)이고 `data_off`가 타입에 의존하지 않으므로, 확정 후 디스크립터를 재finalize(`kind/size/alignby/off/first_var_col` 갱신)해도 기존 튜플을 그대로 읽을 수 있다. 특수 규칙 없음.
- 확정 전 VARIABLE 컬럼은 디스크립터에서 "가변"으로 두어 `first_var_col`을 앞당긴다(상수 접두가 짧아지는 비용은 확정 전까지만).
- 조립기가 VARIABLE 컬럼에 non-NULL 값을 받으면 `assert` (기존 `qfile_unify_types` 계약과 동일).

---

## 9. in-place 덮어쓰기 계약 (#185 반영)

- 5지점(orderby_num·inst_num BIGINT 8B, ISLEAF/ISCYCLE INT 4B, parent_pos 44B 상수 → 1B 헤더 44)은 모두 "bound → 동일 인코딩 크기". 접근자 `qfile_tuple_overwrite_fixed(tpl, layout, col, dbval)`가 assert: 값 non-NULL, 기존 열 non-NULL(비트맵), 도메인 타입 일치, `pr_data_writeval_disk_size == size[col]`(가변이면 헤더 디코드 `L`과 일치·헤더 크기 불변).
- 새 포맷에서는 값 헤더가 없으므로 "헤더까지 다시 쓰는" 경로(`qdata_copy_db_value_to_tuple_value`로 orderby_num 재기록)는 구조적으로 사라진다 — 본문 전용 접근자만 존재.

---

## 10. 정렬 레코드 (`P_sort_key`)

- 본문 = 키 컬럼만으로 구성한 **정방향 전용 미니 튜플**(hdr 4B, 비트맵·정렬·가변 규칙 동일, ). `A_sort_key`의 `offset[]`·0=NULL 규약은 유지(#186).
- 비교자 입력: 본문 포인터(고정: 정렬된 위치 → `data_cmpdisk`; 가변: 헤더 뒤 비정렬 → `index_cmpdisk`, 없으면 정렬 스크래치 복사 후 `data_cmpdisk`). `qfile_compare_partial_sort_record`의 `PTR_ALIGN(body, MAX_ALIGNMENT)` 는 미니 튜플 시작을 4B로 맞추는 것으로 대체.

---

## 11. 바이트 배치 예시와 크기표

표기: `F` = forward-only(hdr 4), `B` = backward_capable(hdr 8). 현행 = `8 + Σ(8 + ALIGN8(size))`, NULL은 헤더 8B만(`list_file.c:1926`, `query_opfunc.c:397`).

### (INT, INT) = (7, 9), NULL 없음
```
F: 00 00 00 0C | 00 00 00 07 | 00 00 00 09            len=12
B: 00 00 00 10 | pp pp pp pp | 00 00 00 07 | 00 00 00 09   len=16
```

### (INT, NULL, BIGINT) = (7, NULL, 5) — has-null, bitmap 1B `0b101 = 0x05`
```
F: 80 00 00 14 | 05 -- -- -- | 00 00 00 07 | 00 00 00 00 00 00 00 05
   len(hasnull|20) bitmap+pad→data_off=8   INT@0        BIGINT@4 (4B 정렬, memcpy 읽기)   total 20
B: 80 00 00 18 | pp pp pp pp | 05 -- -- -- | INT | BIGINT        data_off=12, total 24
```
같은 스키마 NULL 없음 (7, 3, 5): F `data_off=4`, INT@0, INT@4, BIGINT@8 → **20**; B `data_off=8` → **24**.

### (VARCHAR 'abc', INT) = 본문 `03 61 62 63`(pr_type 접두 1B + 3B)
```
F: 00 00 00 10 | 04 | 03 61 62 63 | -- -- -- | 00 00 00 09        포맷 hdr 1B(L=4), INT는 ALIGN4(5)=8, total 16
```

### (INT, VARCHAR 'abc'): F: INT@0, hdr@4(1B), 본문@5..8 → 9 → ALIGN4 = **12**. B: 8+9=17 → **20**.

### (INT, SET 40B 본문): INT@0, SET hdr@4 (1B, L=40), 본문@5..44 → 45 → ALIGN4 → F 4+48 = **52** (읽기 시 40B 스크래치 복사).

### 크기표 (bytes/tuple)

| 스키마 | 현행 | 새 F | 새 B | 비고 |
|---|---|---|---|---|
| (INT) | 24 | 8 | 12 | |
| (INT, INT) | 40 | 12 | 16 | |
| (BIGINT) | 24 | 12 | 16 | |
| (INT, BIGINT) — orderby_num/inst_num 히든 컬럼이 붙은 리스트의 최소형 | 40 | 16 | 20 | §15 A/B안이었으면 24 |
| (INT, INT, BIGINT) | 56 | 20 | 24 | |
| (INT, NULL, BIGINT) | 48 | 20 | 24 | 비트맵 1B + 패딩 3B |
| (DOUBLE, DOUBLE) — SUM/AVG 결과 | 40 | 20 | 24 | |
| (VARCHAR 'abc', INT) | 40 | 16 | 20 | 현행: 문자열 `ALIGN8(ALIGN4(3+2))=8`+헤더 8 |
| (INT, VARCHAR 'abc') | 40 | 12 | 20 | |
| (INT, SET 40B) | 72 | 52 | 56 | 1B 헤더, 읽기 시 스크래치 복사 |
| 100×INT, NULL 없음 | 1608 | 404 | 408 | |
| 100×INT, NULL 1개 | 1600 | 416 | 420 | 비트맵 13B → data_off 20(F)/24(B) |
| TPC-H Q1 집계 키+측정 (CHAR(1)×2, DOUBLE×5, BIGINT) | 136 | 60 | 64 | CHAR(1) 가변 헤더 1B+본문 2B ×2 = 6B, DOUBLE ALIGN4(6)=8부터 40B, BIGINT 8B → 56 + hdr |

---

## 12. 불변식 / assert 목록 (접근자·조립기가 지켜야 할 것)

1. `len & 0x7FFFFFFF ≥ hdr_size`, `len % 4 == 0`.
2. has-null ⇔ 비트맵에 0비트가 `type_cnt` 안에 존재.
3. 후행 비트맵 비트 == 0.
4. 상수 접두 컬럼 위치 == 증분 deform으로 계산한 위치(디버그에서 교차 검증, PG `first_null_attr`의 slow-path 검증과 같은 방식).
5. 가변: 기록 바이트 수 == `L`(§6.3); `index_readval` 있는 타입은 `data_writeval` 호출 금지, 없는 타입은 스크래치 경유만.
6. 고정: 위치 % alignby == 0.
7. `qfile_connect_list`/`qfile_append_list`/`qfile_duplicate_list`: 두 리스트의 `hdr_size`·`type_cnt` 일치(#184).
8. in-place: §9의 4개 assert.
9. `DB_TYPE_VARIABLE` 컬럼에 non-NULL 조립 시 assert.

---

## 13. 이 티켓이 넘기는 것

- 디스크립터 자료구조·pack/unpack·복제(#181): 여기서 요구하는 필드는 `hdr_size, bitmap_size, data_off[2], type_cnt, first_var_col`, 컬럼별 `{kind(fixed|var), var_access(direct|scratch), size, alignby, off}`. `or_pack_listid`는 변경 불필요(클라이언트가 `type_list`로 재계산, #184). **[#181 정정] `hdr_size`는 도메인에서 파생 불가 → pack에 int 1개(layout flags) 추가(D-181-9). `first_var_col`은 `first_non_cached_col`로 개명(D-181-4).**
- 접근자 API·deform 캐시·조립기 시그니처·정렬 레코드 함수 5개(#182). 조립기는 size→fill 2패스(#186).
- 지도 fog 해소: "4B 헤더 뒤 BIGINT 패딩"(D-180-3/4: 8B 타입도 4B 정렬이라 패딩 자체가 없음), "가변 1B 헤더 판별 규칙"(D-180-5/6), "정렬 비교자의 헤더 스킵과 OR 접두 중복"(§6.1 이중 접두 인지, §10), "64+ 컬럼·오버플로 비트맵"(§2.1, §3), "`OR_GET_DOUBLE` UB memcpy 통일"(§5, PR-1 조건).
- 새로 드러난 사항: `mr_data_cmpdisk_bit`의 `OR_GET_INT` 캐스트 → 가변 비교자는 `index_cmpdisk` 필수(D-180-8). 가변 타입은 단일 규칙(D-180-5)이며 정렬 요구 타입은 접근자 복사로 해결 — 지도 Notes의 "가변은 1B/4B 길이 헤더"와 일치.

---

## 14. 검증 추가 (2026-09-02, 사용자 반응에 대한 더블체크)

### 14.1 D-180-3 이 정말 PG 방식인가 → **예**
- `heap_form_minimal_tuple` (`src/backend/access/common/heaptuple.c:1399-1457`): `if (hasnull) len += BITMAPLEN(natts); hoff = len = MAXALIGN(len); /* align user data safely */` → `t_hoff = hoff + MINIMAL_TUPLE_OFFSET`, 값은 `(char*)tuple + hoff`부터. `heap_form_tuple`(`:1033-1101`), `heap_expand_tuple`(`:849, :877`)도 동일 식. 즉 **비트맵 크기를 더한 뒤 한 번 MAXALIGN** — D-180-3의 `data_off = ALIGN(hdr + bitmap, tuple_alignby)`와 같은 구조.
- 오프셋 테이블은 하나: `CompactAttribute.attcacheoff`(`tupdesc.h:70`, "fixed offset into tuple, if known, or -1")는 **`t_hoff` 기준** 상대 오프셋이며 `TupleDescFinalize`(`tupdesc.c:546-555`)가 첫 가변 컬럼 전까지만 채운다. deform은 `tp = tup + t_hoff` 후 `fetch_att(tp + attcacheoff)` (`execTuples.c:1157-1184`: "We can use attcacheoff up until the first NULL … `firstNonCacheOffsetAttr = Min(firstNonCacheOffsetAttr, firstNullAttr)`"). has-null 여부로 테이블을 나누지 않고 `t_hoff`가 흡수한다 — 우리 `data_off[2]`와 동일.
- 차이 하나: PG는 항상 `MAXALIGN`(8). 우리는 상수 4(§15 C안). 튜플 시작이 4B 정렬(페이지 헤더 32B + 길이 반올림)이므로 상대 정렬 == 절대 정렬이 성립한다.

### 14.2 PG는 JSON을 어떻게 다루나 → **비정렬 저장 + 읽을 때 정렬 사본**
- `jsonb`는 `typlen -1`(varlena), **`typalign 'i'`**, `typstorage 'x'` (`src/include/catalog/pg_type.dat:450-453`; `json`/`text`/`numeric`/`bytea`도 전부 `typalign 'i'`).
- 저장: `heap_fill_tuple`/`fill_val` (`heaptuple.c:355-365`) — `attispackable && VARATT_CAN_MAKE_SHORT(val)`(본문 ≤126B)이면 `SET_VARSIZE_SHORT` 1B 헤더로 **정렬 없이** 기록, 아니면 `att_nominal_alignby(data, attalignby)`로 4B 정렬 후 4B 헤더. 즉 PG도 "같은 컬럼이 튜플마다 정렬/비정렬"이며 그래서 §4.1의 피크 트릭이 필요했다.
- 읽기: `DatumGetJsonbP` = `PG_DETOAST_DATUM` (`src/include/utils/jsonb.h:401-403`) → `detoast_attr` (`src/backend/access/common/detoast.c:175-185`): `VARATT_IS_SHORT`면 **`palloc` + `memcpy`로 4B 헤더 정렬 사본을 만든 뒤** `JsonbContainer`의 `uint32` 필드를 읽는다. 즉 PG는 정렬을 **읽는 쪽에서 복사로 회복**한다.
- CUBRID 대응: `mr_data_readval_json`/`mr_data_cmpdisk_json`은 `db_json_deserialize(buf)`가 `or_get_int` (`src/compat/db_json.cpp:4054-4120`, `ASSERT_ALIGN 4`)를 직접 버퍼에 건다. 선택지는 (i) **4B 정렬 위치에 두기(v0 초안)** — 복사 0회, 헤더 3B + 패딩 ≤3B 비용; (ii) PG식 비정렬 저장 + 접근자에서 정렬 스크래치로 memcpy 후 파싱 — JSON은 어차피 파싱으로 힙 문서를 만들므로 복사 1회 추가 비용은 작지만, 접근자에 "타입별 복사 분기"가 생기고 SET/ELO도 같은 처리를 해야 한다. 초안은 (i)였으나 **사용자 결정(예외 없는 단일 규칙)으로 (ii) 채택** — D-180-5·§6.2 반영. 복사 비용은 #193에서 JSON/SET 리스트가 실측 병목일 때만 재검토.

### 14.3 D-180-2/6/8 을 전 타입에 적용해도 현재 코드가 안전한가 → **예, 조건 3개**
pr_type 테이블(`object_primitive.c:897-1763`, NCHAR/VARNCHAR는 `tp_Char`/`tp_String` 별칭 `:1696-1697`) 전수 점검:

| 부류 | 타입 | 새 포맷에서 쓰는 함수 | 정렬 민감 연산 | 판정 |
|---|---|---|---|---|
| FIXED alignby 2 | SHORT, ENUMERATION | `data_*`, `data_cmpdisk` (`OR_GET_SHORT` 캐스트) | 2B 위치 보장 | ✓ |
| FIXED alignby 4 | INT, FLOAT, TIME, TIMESTAMP(+LTZ/TZ), DATE, DATETIME(+LTZ/TZ), MONETARY, OBJECT, OID | `data_*`, `data_cmpdisk` (`OR_GET_INT`/`OR_GET_OID` 캐스트, MONETARY amount는 memcpy) | 4B 위치 보장 | ✓ |
| FIXED alignby 4 (8B 타입) | BIGINT, DOUBLE, RESULTSET | `data_*` (BIGINT memcpy, RESULTSET `or_put_bigint` assert 4); DOUBLE은 `OR_GET_DOUBLE` 캐스트 → **memcpy로 수정(PR-1)** | 4B 위치 = 힙과 동일 | ✓ (조건 4) |
| VAR (index_* 직접) | CHAR/NCHAR, VARCHAR/VARNCHAR | `index_writeval/readval/cmpdisk` → `mr_*_string/char_internal(CHAR_ALIGNMENT)`: `or_put_byte`/`or_put_data`, `OR_GET_BYTE`, `or_get_data`; `size=L` 전달 시 `or_advance`/`or_skip_varchar_remainder(…, CHAR_ALIGNMENT)` 패딩 스킵 없음 (`:mr_readval_string_internal`) | 없음 | ✓ |
| VAR (index_* 직접) | BIT(n) | `mr_index_cmpdisk_bit` → `mr_cmpdisk_bit_internal(CHAR_ALIGNMENT)` **memcpy 분기** (`:13375-13392`) | `data_cmpdisk_bit`(INT_ALIGNMENT)는 `OR_GET_INT(mem)` 캐스트 → **사용 금지** | ✓ (조건 1) |
| VAR (index_* 직접) | VARBIT | `index_cmpdisk` → `data_cmpdisk_varbit`: `or_init` + `or_get_varbit_length`(byte + `or_get_data`) | 없음 | ✓ |
| VAR (index_* 직접) | NUMERIC | `index_*` → data 위임: `or_put_data`, `OR_GET_BYTE`, `or_init`→readval→`numeric_db_value_compare` | 없음 | ✓ |
| VAR (스크래치 복사) | SET/MULTISET/SEQUENCE, JSON, ELO/BLOB/CLOB, VARIABLE, SUBSTRUCTURE, VOBJ, MIDXKEY(방어) | 정렬 스크래치 memcpy 후 `data_*` (`or_put_int`/`or_get_int`/`or_put_bigint` — 모두 `ASSERT_ALIGN 4`) | 스크래치가 8B 정렬이므로 충족 | ✓ |
| 제외 | NULL, POINTER, ERROR | disksize 0, 리스트 값으로 출현 불가 | — | 조립기 assert |

**조건 (접근자 API 티켓 #182·PR-1 #189·PR-2 #190에 넘김):**
1. 정렬 비교자 선택(`list_file.c:4507-4538`의 `sort_f = domain->type->data_cmpdisk`)을 가변 타입은 `index_cmpdisk`(있으면), 없으면 스크래치 복사 + `data_cmpdisk`로. BIT(n)에서 이 조건을 놓치면 디버그가 아닌 **릴리스에서도** 비정렬 캐스트가 발생한다(x86은 동작, 표준상 UB).
2. `index_readval`이 있는 가변 타입의 리더는 `index_readval(buf, val, dom, size=L, …)`로 호출하고 `data_readval`을 부르지 않는다(INT_ALIGNMENT 리더는 NUL+패딩을 건너뛰어 `L`을 넘어 읽음). 클라이언트 `cursor.c:441,489`도 동일 — `pr_type` 테이블은 공용이라 클라이언트 라이브러리에서도 `index_*` 사용 가능.
3. pr_type을 거치지 않고 튜플 값을 직접 캐스트하는 현행 지점(`cursor_get_oid_from_tuple` `(OID*)(tpl+8)` `cursor.c:628`, in-place `OR_PUT_INT(tpl+8)` `list_file.c:1944,1949,2015`, 정렬 레코드 `PTR_ALIGN(…, MAX_ALIGNMENT)` `list_file.c:3538-4256`)은 전부 지도의 19파일 접점 조사에 포함돼 있으며 접근자로 교체된다. 새 포맷에서 남는 직접 캐스트는 접근자 내부 한 곳이어야 한다.

4. `OR_GET_DOUBLE`/`OR_GET_FLOAT`(`object_representation.h:158-165`)를 memcpy 기반으로 수정(PR-1). 정렬 비교자 `mr_data_cmpdisk_double`·`mr_index_cmpdisk_double`(`COPYMEM`, x86 캐스트)이 4B 위치를 읽으므로 이 수정이 없으면 표준상 UB(x86은 동작).

비트맵(D-180-2)과 길이 헤더(D-180-6)는 타입에 독립이다: 헤더 4B 길이 상한 `0x7FFFFFFF` > `DB_MAX_STRING_LENGTH(0x3FFFFFFF)` + pr_type 접두 9B.

---

## 15. `tuple_alignby` 규칙 재검토 (사용자 요청, `cpp-perf-rules` 기준)

### 15.1 v0 초안이 왜 `{4,8}` + "VARIABLE=8 고정" 이었는지 (추적)
1. **#183 D-183-1**: BIGINT/DOUBLE을 8B 정렬하자 — 이유는 성능이 아니라 `OR_GET_DOUBLE`의 `*(UINT64*)` 캐스트(`object_representation.h:164`)가 4B 위치에서 UB라는 것. CUBRID가 실제 assert하는 최대 정렬은 4이고, 힙은 DOUBLE을 4B에 저장한다(`pr_type::alignment` DOUBLE/BIGINT = 4, `DB_ATT_ALIGN = INT_ALIGNMENT`).
2. 8B 컬럼이 있으면 튜플 시작도 8 정렬이어야 하므로 `tuple_alignby`가 8이 되고, **INT 전용 리스트까지 8로 끌려가는 것을 피하려고** 리스트별 `{4,8}`이 됐다.
3. `{4,8}`이 리스트별이 되자 늦은 도메인 확정(VARIABLE→BIGINT, §8)이 open 뒤에 `tuple_alignby`를 바꿀 수 있어 "open 시 고정 + VARIABLE은 8로 계산"이라는 규칙이 추가됐다.

즉 3은 2에서, 2는 1에서 나온 **연쇄**다. 1의 전제(8B 값을 캐스트로 읽는다)를 버리면 — 새 접근자는 어차피 memcpy로 읽는다(§5, SER-03) — 연쇄 전체가 사라진다.

### 15.2 선택지
| | A. 항상 8 (PG `MAXALIGN`) | B. v0 초안 `{4,8}` + 고정 | C. 항상 4 (힙 관례) |
|---|---|---|---|
| 규칙 수 | 1 | 3 (리스트별 계산·open 고정·VARIABLE=8) | 1 |
| BIGINT/DOUBLE 위치 | 8B | 8B | **4B** (힙과 동일) |
| 8B 읽기 방식 | 캐스트 가능 | 캐스트 가능 | **memcpy 필수**(SER-03; 컴파일러가 단일 `mov`로 내림 — CPP-CLOW `memcpy(d,s,8)` 항목, 비용 0) |
| 늦은 도메인 규칙 | 불필요 | 필요 | 불필요 |

### 15.3 압축 비교 (bytes/tuple, forward-only 헤더 4B 기준; 괄호는 backward 8B)
| 스키마 | A 항상 8 | B `{4,8}` | C 항상 4 | 비고 |
|---|---|---|---|---|
| (INT, INT) | 16 (16) | 12 (16) | 12 (16) | |
| (INT, BIGINT) — **orderby_num/inst_num 히든 컬럼이 붙은 모든 리스트의 최소형**(#185: 둘 다 BIGINT) | 24 (24) | 24 (24) | **16 (20)** | B는 BIGINT 존재로 8이 되어 A와 같아짐 |
| (BIGINT) | 16 (16) | 16 (16) | 12 (16) | |
| (INT, NULL, BIGINT) | 24 (32) | 24 (32) | 20 (24) | |
| (DOUBLE, DOUBLE) — SUM/AVG 집계 결과 | 24 (24) | 24 (24) | 20 (24) | |
| (INT, VARCHAR 'abc') | 24 (24) | 12 (20) | 12 (20) | A: data_off 8 + 9 → ALIGN8 |
| (VARCHAR 'abc', INT) | 24 (24) | 16 (20) | 16 (20) | |
| 100×INT | 408 (408) | 404 (408) | 404 (408) | |
| TPC-H Q1 집계행 (CHAR1×2, DOUBLE×5, BIGINT) | 64 (64) | 64 (64) | 60 (64) | |

관찰: **B가 A보다 나은 경우는 "8B 타입이 하나도 없는 리스트"뿐**인데, ORDER BY/LIMIT(orderby_num), inst_num, COUNT(BIGINT), SUM/AVG(DOUBLE/NUMERIC)가 붙는 순간 8B 컬럼이 생겨 B=A가 된다. C는 모든 행에서 A·B 이하이고, 8B 컬럼이 있는 행에서 A·B 대비 4~8B(17~33%) 작다. 절감은 페이지 수·spill I/O·memcpy 바이트로 직결된다(우선순위 절차 2단계 "접근 데이터 줄이기", MEM-01/02).

### 15.4 C의 오버헤드 (정량)
- **비정렬 8B 로드**: x86-64에서 64B 캐시라인 안의 비정렬 로드는 정렬 로드와 동일 비용(L1 4–5 cycles, COSTS §0). 4B 정렬 8B 값이 라인 경계를 걸치는 확률은 1/16(offset%64==60)이며 split load는 +1–2 cycles → 8B 컬럼당 기대 비용 ≈ 0.1 cycle. DRAM 접근 1회(200–400 cycles)와 비교하면 무시 가능하고, 절약한 바이트가 라인 수를 줄이는 이득이 더 크다. 벡터화 영향 없음(deform은 스칼라 경로).
- **UB 제거 조건**: 새 접근자의 8B 읽기는 memcpy(SER-03, A11/A39 금지 항목이 현행 `OR_GET_DOUBLE` 캐스트). 정렬 비교자 `mr_data_cmpdisk_double`(캐스트)·`mr_index_cmpdisk_double`(`COPYMEM` — x86에서 캐스트, `porting.h:725-732`)이 4B 위치를 읽게 되므로 **`OR_GET_DOUBLE`/`OR_GET_FLOAT`를 memcpy로 고치는 한 줄 변경**(`object_representation.h:164`; PUT은 이미 memcpy)으로 코드베이스 전체의 UB를 함께 없앤다. 이것은 힙이 수십 년간 4B 위치의 DOUBLE을 캐스트로 읽어온 잠재 UB의 정리이기도 하다.
- **비-x86**: AIX PPC64 빌드 분기 존재(`CMakeLists.txt:642-647`). POWER는 정수/FP 비정렬 로드를 하드웨어가 처리하며, 힙 DOUBLE 4B 저장 선례가 이미 그 플랫폼에서 동작한다. `COPYMEM`이 비-x86에서 memcpy인 것도 같은 방어.
- **측정(MEAS-01)**: 위는 추정이다. #193의 TPC-H parallel=6 기준선 비교에서 C가 A/B 대비 느려지지 않음을 확인해야 하며, 예상은 "중립 또는 바이트 절감만큼 개선".

### 15.5 A의 오버헤드
- 8B 타입이 없는 리스트에서도 +4B, 가변 컬럼이 섞이면 반올림 손실이 최대 +7B(위 표 (INT, VARCHAR) 12→24). 규칙은 가장 단순하고 PG와 글자 그대로 같다.

### 15.6 권고 → **채택 (2026-09-02 사용자 결정: C)**
**C (항상 4)**. 예외 없는 단일 규칙이면서 가장 압축되고, 힙 포맷과 정렬 관례가 같아지며, 늦은 도메인 특수 규칙이 사라진다. 채택 시 변경: D-180-3 → `tuple_alignby = 4` 상수, `data_off = ALIGN4(hdr + bitmap)`; D-180-4 → BIGINT/DOUBLE/RESULTSET alignby 4(#183 D-183-1 롤백 경로 그대로), 모든 8B 읽기는 memcpy; §8의 고정 규칙 삭제(VARIABLE은 단지 "가변" 컬럼); 조건으로 `OR_GET_DOUBLE`/`OR_GET_FLOAT` memcpy 전환을 PR-1 범위에 추가.
