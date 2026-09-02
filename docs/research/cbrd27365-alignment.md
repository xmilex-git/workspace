# CBRD-27365 연구: 자연 정렬(INT 4B 등)이 pr_type / OR_* (역)직렬화에 안전한가

- 티켓: xmilex-git/workspace #183 (지도 #179 의 일부)
- 대상 소스: `/home/cubrid/dev/cubrid` develop `77bd76bab` (2026-09-02), PostgreSQL `/home/cubrid/dev/postgres` `5713b437abe` (20devel)
- 작성일: 2026-09-02
- 모든 경로는 특별한 언급이 없으면 CUBRID 체크아웃 기준.

## 0. 결론 요약

1. **안전하다.** `pr_type::data_readval/data_writeval` 는 모두 `or_get_*/or_put_*` 를 거치며, 그 함수들이 요구(assert)하는 정렬은 **INT_ALIGNMENT(4)** 이 최대다(SHORT/ENUM 은 2). 8바이트 타입(BIGINT/DOUBLE)조차 4바이트 정렬만 assert 한다. 자연 정렬(INT 4, SHORT 2, BIGINT/DOUBLE 8)은 이 요구를 모두 만족하므로 기존 (역)직렬화 코드를 **수정 없이** 그대로 쓸 수 있다.
2. **현재의 `DB_ALIGN(disk_size, MAX_ALIGNMENT)`(8B)는 관성이다.** 어떤 접근자도 8바이트 정렬을 요구하지 않는다. 원저자 주석 "I don't know if the following is still true." 가 이를 자백하고 있고, git 이력상 2014 초기 import 이전(레거시)부터 있던 규칙이다. 실제 비용은 INT 컬럼 하나가 16B(헤더 8 + 값 4 + 패딩 4)를 차지하는 것.
3. **가변 값은 "정렬하지 않고 길이 헤더로만 판별"이 더 단순하고 안전하다.** PG 의 패딩바이트 피크 트릭은 "4B 헤더 varlena 는 정렬하고 1B 헤더 varlena 는 정렬하지 않는" PG 고유의 혼합 규칙 때문에 필요한 것이다. 가변 값을 항상 비정렬로 두면 판별 자체가 불필요해지고, 트릭이 의존하는 두 불변식(패딩은 0, 1B 헤더는 비영)도 유지할 필요가 없다.
4. **함정 하나(중요):** 문자열 계열 `data_writeval` 은 값 뒤를 **절대 주소 기준**으로 4B 패딩(`or_put_align32`)하고, `data_lengthval` 은 버퍼 시작이 4B 정렬이라는 가정으로 크기를 계산한다. 가변 값을 비정렬 위치에 두면서 `data_writeval` 을 그대로 호출하면 **lengthval ≠ 실제 기록 크기** 가 된다. 새 포맷의 가변 값 기록은 `index_*` 계열(CHAR_ALIGNMENT, 패딩 없음)이나 전용 원시 복사를 써야 한다.

---

## 1. (a) OR_GET_*/OR_PUT_* 와 pr_type 접근자의 비정렬 포인터 처리

### 1.1 매크로 계층 (`src/base/object_representation.h`)

| 매크로 | 구현 방식 | 비정렬 안전? | 근거 |
|---|---|---|---|
| `OR_GET_BYTE/OR_PUT_BYTE` | `*(unsigned char *)` | 예 | `object_representation.h:103-107` |
| `OR_GET_SHORT/OR_PUT_SHORT` | `*(short *)` 캐스트 + `ntohs/htons` | **아니오(정렬 캐스트)** | `:109-113` |
| `OR_GET_INT/OR_PUT_INT` | `*(int *)` 캐스트 + `ntohl/htonl` | **아니오(정렬 캐스트)** | `:115-119` |
| `OR_GET_INT64/OR_PUT_INT64` (= `OR_GET_BIGINT/OR_PUT_BIGINT`) | `memcpy` 후 `swap64` | 예 | `:121-146` |
| `OR_PUT_FLOAT` | `memcpy` | 예 | `:148-152` |
| `OR_GET_FLOAT` | `*(UINT32 *)` 캐스트 + `ntohf` | **아니오** (PUT 과 비대칭) | `:154-155` |
| `OR_PUT_DOUBLE` | `memcpy` | 예 | `:158-162` |
| `OR_GET_DOUBLE` | `*(UINT64 *)` 캐스트 + `ntohd` | **아니오** (PUT 과 비대칭) | `:164-165` |
| `OR_GET_PTR/OR_PUT_PTR` (64bit) | `*(UINTPTR *)` 캐스트 | 아니오 (컬럼 타입 아님) | `:171-172` |
| `OR_GET_TIME/UTIME/DATE` | `OR_GET_INT` 위임 | INT 규칙 | `:177-205` |
| `OR_GET_TIMESTAMPTZ` | `OR_GET_INT` ×2 (+0, +4) | INT 규칙 | `:189-199` |
| `OR_GET_DATETIME` | `OR_GET_INT` ×2 (+0, +4) | INT 규칙 | `:207-217` |
| `OR_GET_DATETIMETZ` | `OR_GET_DATETIME` + `OR_GET_INT`(+8) | INT 규칙 | `:219-231` |
| `OR_GET_MONETARY` | type: `OR_GET_INT`(+0); amount: **`memcpy`** 8B(+4) 후 `OR_GET_DOUBLE` 를 로컬에 적용 | type 만 INT 규칙, amount 는 안전 | `:233-247` |
| `OR_GET_OID/OR_PUT_OID` | `OR_GET_INT`(+0) + `OR_GET_SHORT`(+4, +6) | INT 규칙 | `:281-293` |
| `OR_MOVE_DOUBLE` (`src/storage/byte_order.h:87-88`) | `MOVING_VAN` 유니온의 `unsigned int[2]` 대입 | 4B 캐스트 | IA64 만 memcpy |

요약: **INT/SHORT/FLOAT/DOUBLE 읽기는 정렬된 포인터를 전제한 캐스트**다. x86-64 하드웨어는 비정렬 스칼라 로드를 허용하므로 실무상 동작하지만, C 표준상 UB 이고 컴파일러 벡터화 시 깨질 수 있다. 8바이트 타입은 memcpy 로 이미 안전하다(MONETARY amount 도).

### 1.2 `or_buf` 계층 — 실제로 assert 되는 정렬 요구

모든 `pr_type::data_readval/data_writeval` 고정폭 구현은 `or_get_*/or_put_*` 로 위임한다(`src/object/object_primitive.c:2405-2430` INT, `:2574-2601` SHORT, `:2746-2772` BIGINT, `:2921-2947` FLOAT, `:3111-3138` DOUBLE, `:3290-3316` TIME, `:3501-3527` TIMESTAMP, `:3730-3752` TIMESTAMPTZ, `:3961-3994` DATETIME, `:4303-4325` DATETIMETZ, `:4546-4572` MONETARY, `:4729-4755` DATE, `:5225-5370` OBJECT, `:6636-6660` OID, `:14345-14370` ENUM).

`or_get_*/or_put_*` 는 진입 시 `ASSERT_ALIGN(buf->ptr, X)` (`object_representation.h:1051`: `PTR_ALIGN(ptr, alignment) == ptr`) 를 건다:

| 함수 | assert 정렬 | 위치 (`src/base/object_representation.h`) |
|---|---|---|
| `or_put_short / or_get_short` | `SHORT_ALIGNMENT` (2) | `:1652-1680` |
| `or_put_int / or_get_int` | `INT_ALIGNMENT` (4) | `:1689-1716` |
| `or_put_bigint / or_get_bigint` | **`INT_ALIGNMENT` (4)** — 8 아님 | `:1726-1755` |
| `or_put_float / or_get_float` | `FLOAT_ALIGNMENT` (4) | `:1764-1793` |
| `or_put_double / or_get_double` | **`INT_ALIGNMENT` (4)** — 8 아님 | `:1802-1830` |
| `or_*_time/utime/date/datetime/timestamptz/datetimetz` | `INT_ALIGNMENT` (4) | `:1845-2039` |
| `or_put_oid / or_get_oid` | `INT_ALIGNMENT` (4) | `:2454-2491` |
| `or_put_monetary / or_get_monetary` | `INT_ALIGNMENT` (4) | `src/object/object_representation.c:506-574` |
| `or_put_data / or_get_data` (raw) | 없음 (`memcpy`) | `:2049-2071` |
| `or_put_byte / or_get_byte` | 없음 | `:1618-1643` |

즉 **CUBRID 자체가 `data_*` 경로에서 계약으로 요구하는 최대 정렬은 4B** 다. 8바이트 타입에 자연 정렬 8 을 주면 4 의 배수이므로 자동 충족. 자연 정렬을 8 대신 4 로 낮춰도(BIGINT/DOUBLE 을 4B 경계에) assert 는 통과하나, `OR_GET_DOUBLE` 의 `*(UINT64*)` 캐스트가 4B 정렬 주소를 읽는 UB 가 된다(§1.4 힙 선례 참조).

### 1.3 `index_*` 계열 — 이미 존재하는 "비정렬 전용" (역)직렬화

B-tree midxkey 요소는 널맵/오프셋 헤더 뒤에 패딩 없이 연속 패킹된다(`pr_midxkey_get_element_offset`, `object_primitive.c:9208-9272`; `or_multi_header_size`, `object_representation.h:2619`). 그래서 같은 pr_type 에 **정렬을 전제하지 않는 두 번째 함수군**이 있다:

- `mr_index_writeval_int` → `or_put_data(buf, &i, 4)` (`object_primitive.c:2433-2440`), `mr_index_readval_int` → `or_get_data` (`:2443-2462`)
- BIGINT/DOUBLE/FLOAT/SHORT/DATETIME/TIMESTAMPTZ/DATETIMETZ/MONETARY/OID 모두 `or_get_data/or_put_data` 필드별 memcpy (`:2785-2806`, `:3151-3172`, `:2950-2957`, `:2604-2611`, `:4016-4032`, `:3755-3771`, `:4328-4348`, `:4575-4589`, `:6686-6715`)
- 비교자 `mr_index_cmpdisk_*` 는 `COPYMEM` (`:2465-2475`, `:2809-2819`, `:3175-3185`, `:4097-4113`, `:4621-4631`, `:6719-6736`)
- `COPYMEM` (`src/base/porting.h:724-732`): **X86/WINDOWS 에서는 `*(type*)dst = *(type*)src` 캐스트, 그 외 플랫폼은 `memcpy`** — 코드베이스가 "x86 은 비정렬 접근을 하드웨어가 허용한다"는 사실을 알고 의도적으로 의존하되 fallback 을 두고 있다는 직접 증거.
- 문자열: `mr_index_writeval_string` → `mr_writeval_string_internal(buf, value, CHAR_ALIGNMENT)` (`:10777-10779`), `data_` 버전은 `INT_ALIGNMENT` (`:10796-10799`).

주의: `index_*` 는 **호스트 바이트 오더**(htonl 없음)다. 임시 리스트 튜플은 CS 모드에서 서버→클라이언트(`src/query/cursor.c:441,489` 가 `or_init` + `data_readval` 로 읽음)로 페이지 바이트가 그대로 전송되므로, 값 인코딩은 기존 `data_*`(네트워크 오더) 를 유지하는 것이 호환성상 안전하다. `index_*` 는 "비정렬 위치에 쓰는 것이 안전하다"는 선례로 인용할 뿐, 새 포맷의 값 인코딩으로 그대로 채택하자는 뜻은 아니다(§5 권고 참조).

### 1.4 힙 레코드 선례 — 8바이트 타입도 4B 정렬로 저장 중

- `pr_type::alignment` 필드(`src/object/object_primitive.h:90`) 값: INT 4, SHORT 2, **BIGINT 4, DOUBLE 4**, TIME/DATE/TIMESTAMP(+TZ/LTZ)/DATETIME(+TZ/LTZ) 4, MONETARY 4, OBJECT/OID 4, ENUM 2, NUMERIC 1, CHAR/VARCHAR/BIT 1 (`src/object/object_primitive.c:922-1749, 11561-15013`).
- 힙 고정 속성 오프셋은 `DB_ATT_ALIGN` = `INT_ALIGNMENT` 로만 정렬(`src/base/memory_alloc.h:100-101`; 사용처 `src/base/object_representation_sr.c:3079,3276`, `src/object/class_object.c:7157-7175`). 속성은 `order_atts_by_alignment` 로 정렬 요구 내림차순 재배치(`src/object/schema_manager.c:10032-10058`).
- 따라서 **DOUBLE/BIGINT 를 4B 경계에서 `OR_GET_DOUBLE` 캐스트로 읽는 것은 CUBRID 힙이 수십 년간 해온 일**이다. 새 포맷에서 8B 타입을 8 로 정렬하면 이보다 더 보수적이다.

### 1.5 현재 임시 튜플이 정렬을 실제로 쓰는 지점

- 값 읽기: `or_init(&buf, tuple + 8, len)` → `data_readval` (`src/query/list_file.c:830-848, 1022-1025, 1062-1063`, `src/query/fetch.c:4095-4097, 4670-4692`, `src/query/query_hash_join.c:2965-3008`, `src/query/cursor.c:441-493`).
- 직접 캐스트: `cursor_get_oid_from_tuple` 이 `(OID *)(tuple_p + 8)` 로 구조체 캐스트(`src/query/cursor.c:628`) → OID 값은 최소 4B 정렬 필요(자연 정렬 4 로 충족).
- in-place 덮어쓰기: `OR_PUT_INT(tuple_p + 8, v)` (`src/query/list_file.c:1944, 1949, 2015`) → INT 4B 정렬.
- 정렬 레코드 비교: `qfile_compare_partial_sort_record` 가 `PTR_ALIGN(body, MAX_ALIGNMENT)` 후 `d0 = fp0 + 8` 을 `data_cmpdisk`(`OR_GET_*` 캐스트, assert 없음)에 넘김(`src/query/list_file.c:4253-4284`; sort_f 지정 `:4507-4538`). 8B 정렬은 **스스로 만든 것**이며 cmpdisk 자체는 4B 로 충분(`mr_data_cmpdisk_int` `object_primitive.c:2478-2488` 등).

---

## 2. (b) `DB_ALIGN(disk_size, MAX_ALIGNMENT)` 는 요구인가 관성인가 → **관성**

증거:

1. `src/query/query_list.h:224-227` 주석 "Each tuple start / value header / value is aligned with MAX_ALIGNMENT" 와 `src/query/list_file.c:1034-1036` 동일 주석. `git blame` 결과 두 곳 모두 `6522201dab` (2014-04-21, 리포지토리 초기 import 계열) — 즉 git 이력 이전의 레거시 설계.
2. `qdata_copy_db_value_to_tuple_value` (`src/query/query_opfunc.c:356-408`): `:393` **"I don't know if the following is still true."** 바로 아래 `:397 align = DB_ALIGN(val_size, MAX_ALIGNMENT)`. `:394-395` 보충 주석(2016)은 "이미 8 정렬돼 있으니 val_size 만으로 다음 헤더 정렬을 맞출 수 있다"는 *자기 참조* 설명일 뿐 어떤 접근자 요구도 인용하지 않는다.
3. `qdata_get_tuple_value_size_from_dbval` (`:6336-6396`, `:6390`) 은 2019 리팩터링에서 같은 식을 복제한 것.
4. `MAX_ALIGNMENT` = `DOUBLE_ALIGNMENT` = `sizeof(double)` = 8 (`src/base/memory_alloc.h:71,77`) — 타입별 요구가 아닌 "가장 큰 스칼라" 범용 상수.
5. §1.2 표: 접근자가 assert 하는 최대 정렬은 4. **8B 정렬을 요구하는 접근자는 하나도 없다.** 8B 에 의존하는 코드는 `PTR_ALIGN(…, MAX_ALIGNMENT)` 로 스스로 정렬을 만드는 정렬 레코드 빌더/비교자(`list_file.c:3538,3579,3928,3957,4253,4256`)만이며, 이는 포맷 재설계 시 함께 바뀌는 대상이다.
6. 튜플 시작 8B 정렬은 페이지 헤더 32B(`query_list.h:52`) + 모든 튜플 길이가 8 의 배수(헤더 8 + Σ(8 + DB_ALIGN(size,8)))인 데서 자동으로 나오는 성질이고, 이것이 `or_put_align32` 의 절대 주소 기반 패딩(§4.2)이 lengthval 과 일치하도록 보장한다. 새 포맷에서도 "튜플 시작(또는 값 영역 시작)은 4B 이상 정렬" 이라는 하나의 불변식만 유지하면 된다.

비용(현재): INT 컬럼 = 헤더 8 + `DB_ALIGN(4, 8)` = **16B** (`list_file.c:1926`: `tuple_value_size = DB_ALIGN(tp_Integer.disksize, MAX_ALIGNMENT)`). SHORT 도 16B. OID(8B) 는 16B, DATETIMETZ/MONETARY(12B) 는 24B.

---

## 3. (c) 고정폭 타입 전수표 (`pr_type::is_size_computed() == false`)

`is_size_computed()` 는 `f_data_lengthmem/f_data_lengthval` 이 NULL 인지로 판정(`src/object/object_primitive.h:446-450`). 아래는 pr_type 테이블(`src/object/object_primitive.c`)에서 `disksize != 0` 인 고정폭 타입 전부. "assert 정렬"은 §1.2 의 `or_*` 함수가 실제로 요구하는 값, "자연 정렬"은 가장 큰 구성 필드 크기(구조체 자연 정렬).

| DB_TYPE | pr_type 정의 위치 | disksize | 내부 필드 구성 (`object_representation_constants.h`) | assert 정렬 | 자연 정렬 | `pr_type::alignment` (힙) |
|---|---|---|---|---|---|---|
| SHORT | `:947` | 2 | short | 2 | 2 | 2 |
| ENUMERATION | `:1664` | 2 | unsigned short (`or_put_short`, `:14367-14370`) | 2 | 2 | 2 |
| INTEGER | `:922` | 4 | int | 4 | 4 | 4 |
| FLOAT | `:997` | 4 | float | 4 | 4 | 4 |
| TIME | `:1047` | 4 (`OR_TIME_SIZE` `:103`) | int | 4 | 4 | 4 |
| TIMESTAMP | `:1072` | 4 (`OR_UTIME_SIZE` `:104`) | int | 4 | 4 | 4 |
| TIMESTAMPLTZ | `:1124` | 4 (`OR_UTIME_SIZE`) | int | 4 | 4 | 4 |
| DATE | `:1249` | 4 (`OR_DATE_SIZE` `:105`) | int | 4 | 4 | 4 |
| BIGINT | `:972` | 8 | int64 (memcpy) | **4** | 8 | 4 |
| DOUBLE | `:1022` | 8 | double (GET 은 `*(UINT64*)` 캐스트) | **4** | 8 | 4 |
| TIMESTAMPTZ | `:1097` | 8 (`OR_UTIME_SIZE + sizeof(TZ_ID)` `:114`; TZ_ID = unsigned int `dbtype_def.h:837`) | int @0 + int @4 | 4 | **4** | 4 |
| DATETIME | `:1147` | 8 (`OR_DATETIME_SIZE` `:110`) | int date @0 + int time @4 | 4 | **4** | 4 |
| DATETIMELTZ | `:1199` | 8 (`OR_DATETIME_SIZE`) | int + int | 4 | **4** | 4 |
| OBJECT | `:1282` | 8 (`OR_OID_SIZE` `:67`) | int pageid @0 + short slotid @4 + short volid @6 | 4 | **4** | 4 |
| OID (`*oid*`) | `:1489` | 8 (`OR_OID_SIZE`) | 동일 | 4 | **4** | 4 |
| DATETIMETZ | `:1172` | 12 (`OR_DATETIME_SIZE + sizeof(TZ_ID)` `:117`) | int + int + int tz_id @8 | 4 | **4** | 4 |
| MONETARY | `:1224` | 12 (`OR_MONETARY_SIZE` `:120`) | int type @0 + double amount @4 (memcpy, `:233-247`) | 4 | **4** (amount 가 +4 에 있어 8 정렬 불가능) | 4 |
| RESULTSET | `:1749` | 8 (`sizeof(DB_RESULTSET)` = uint64_t `dbtype_def.h:1103`) | 클라이언트 전용 핸들, 리스트 파일 출현 가능성 낮음 | – | 8 | 4 |

제외/참고:
- `NULL`(`:897`), `POINTER`(`:1432`), `ERROR`(`:1457`) — disksize 0, 디스크 표현 없음.
- **BIT(n)** 은 `variable_p = 0` 이지만 `disksize = 0` 이고 `mr_data_lengthval_bit` 가 있어 `is_size_computed() == true` (`:13458`, `:13051-13088`) → 지도의 결정대로 가변 취급이 맞다. NUMERIC(`:1639`, `variable_p=1`), CHAR(n)(`:12733`) 도 동일.
- `is_always_variable()` 은 신뢰 불가라는 헤더 주석(`object_primitive.h:440-443`) 이 판정 기준을 `is_size_computed()` 로 잡은 것을 뒷받침.

**설계 함의:** 자연 정렬을 "가장 큰 필드" 기준으로 두면 실제로 8 이 필요한 타입은 **BIGINT/DOUBLE 둘뿐**이고, 나머지 8·12B 복합 타입(DATETIME, TIMESTAMPTZ, OID, DATETIMETZ, MONETARY)은 4 다. 레이아웃 디스크립터에는 "disksize" 와 별도로 "alignby" 를 타입별 상수로 두는 것이 맞으며(PG `CompactAttribute.attalignby` 와 동일 개념), 값은 위 표의 "자연 정렬" 열을 권고한다. 4 로 통일(힙 관례)도 코드상 안전하나 `OR_GET_DOUBLE` 캐스트 UB 를 새 포맷까지 가져가는 셈이라 권하지 않는다.

---

## 4. (d) PG 1B 짧은 varlena 헤더 패딩바이트 피크 트릭 vs "가변 값은 정렬하지 않음"

### 4.1 PG 트릭의 정확한 전제

- `src/include/access/tupmacs.h:363-378` (`att_align_pointer`): varlena(attlen == -1)를 만나면 현재 바이트를 **피크**해 `VARATT_NOT_PAD_BYTE(ptr)` (= `*(uint8*)ptr != 0`, `varatt.h:205-206`) 이면 정렬 없이 그 자리에서 읽고, 0 이면 `att_align_nominal` 로 정렬한 뒤 읽는다.
- 성립 조건 (`varatt.h:156-180` 주석): (1) 4B 헤더 varlena 는 **정렬되어** 저장, (2) 1B 헤더는 헤더 자신을 길이에 포함해 **절대 0 이 아님**, (3) **패딩 바이트는 반드시 0** ("We now *require* pad bytes to be filled with zero!"), (4) 리틀엔디안에서 4B 헤더의 첫 바이트 하위 2비트가 00 이므로 첫 바이트가 0 이면 어차피 정렬된 4B 헤더거나 패딩 → 정렬해도 안전.
- 쓰기 측 (`src/backend/access/common/heaptuple.c:349-367`, `heap_compute_data_size` 동 파일): 짧게 만들 수 있으면 헤더 1B 로 변환하고 **정렬 생략**, 아니면 `att_nominal_alignby` 로 정렬 후 4B 헤더 그대로 복사. 즉 **같은 컬럼이 튜플마다 정렬 여부가 달라진다** — 피크가 필요한 이유는 정확히 이것이다.

### 4.2 우리 자연 정렬 규칙 하에서

- 고정 값은 레이아웃 디스크립터의 `alignby` 로 `att_align_nominal` 식 정렬 → 피크 불필요(PG 도 고정 타입은 피크하지 않음).
- 가변 값을 **"항상 비정렬(이전 값 끝 = 시작)"** 로 두면, 가변 값 앞에는 패딩이 존재할 수 없다 → 피크할 대상이 없다. 헤더 1B/4B 판별은 **헤더 첫 바이트의 플래그 비트**로 하면 되고(PG 는 LE 하위 비트, CUBRID varchar 는 `0xFF` 이스케이프 — `or_varchar_length_internal` `object_representation.h:2326-2340`, `pr_write_compressed_string_to_buffer` `object_primitive.c:14713`), 4B 헤더는 memcpy 로 읽으면 정렬 무관.
- PG 트릭을 그대로 얹어도 **논리적으로는 여전히 성립**한다(4B 헤더 첫 바이트를 비영으로 인코딩하면 피크가 항상 "not pad" → 정렬 안 함 → 우리 규칙과 동일 결과). 그러나 그 경우 트릭은 항상 같은 분기를 타는 **죽은 코드**이며, 대신 "패딩은 0 으로 채워야 한다", "1B 헤더는 0 일 수 없다(빈 문자열 길이 0 을 헤더 값 1 로 시프트)" 라는 두 불변식을 코드 전체가 지켜야 하는 부담만 남는다. 이는 오늘의 CUBRID 가 지키지 않는 불변식이다(패딩 memset 은 `!NDEBUG` 에서만: `query_opfunc.c:401-404`).
- 우리 규칙의 유일한 추가 비용: 가변 값 뒤에 오는 **고정 값** 앞에 정렬 패딩이 생길 수 있음(PG 도 동일). 가변 값 뒤 오프셋은 접두 증분 deform 캐시로 해결(지도 결정과 일치).

### 4.3 CUBRID 고유 함정 — 문자열 `data_writeval` 의 절대 주소 패딩

- `pr_write_uncompressed_string_to_buffer` / `pr_write_compressed_string_to_buffer` (`object_primitive.c:14800-14811, 14752-14763`): `align == INT_ALIGNMENT` 이면 NUL 1B + `or_put_align32(buf)`.
- `or_put_align32` (`object_representation.h:1516-1528`): `(UINTPTR) buf->ptr & 3` — **버퍼 시작 오프셋이 아닌 절대 주소** 기준으로 패딩.
- `or_varchar_length_internal(…, INT_ALIGNMENT)` (`:2326-2355`): 길이는 `DB_ALIGN(len, 4)` — **버퍼가 4B 정렬 주소에서 시작한다고 가정**.
- 결론: 가변 값을 4 의 배수가 아닌 주소에 놓고 `data_writeval` 을 호출하면 기록 크기 ≠ `data_lengthval` 이 되어 튜플 길이 계산이 깨진다. 오늘은 값 시작이 항상 8 정렬이라 드러나지 않은 잠복 계약이다. 새 포맷은 (i) `index_writeval/index_readval`(CHAR_ALIGNMENT, 패딩·NUL 없음 — 문자열은 압축 인코딩까지 동일, `:10777-10783`) 을 쓰거나, (ii) 접근자 API 가 문자열/비트/NUMERIC 바이트를 직접 복사해야 한다. 어느 쪽이든 **포맷 명세 티켓에 명문화**할 것.
- 부수 관찰: CUBRID 가변 타입은 이미 자기 서술 길이 접두(varchar 1B/`0xFF`+4B+4B, varbit 1B/`0xFF`+4B `:2080-2098`, numeric `header[0] & 0x7F` `:8764`)를 갖는다. 포맷 레벨 1B/4B 헤더를 추가하면 짧은 문자열은 접두가 2B 가 된다. O(1) 스킵(타입 디스패치 없이)이라는 이점이 있어 지도 결정(포맷 헤더 유지)은 타당하나, 이중 헤더 비용은 인지하고 갈 것.

---

## 5. 권고

**D-183-1 고정 값 정렬:** 레이아웃 디스크립터에 타입별 `alignby` 상수를 두고 §3 "자연 정렬" 열을 채택 — SHORT/ENUM 2, INT/FLOAT/DATE/TIME/TIMESTAMP(+LTZ) 4, TIMESTAMPTZ/DATETIME(+LTZ)/DATETIMETZ/OID/OBJECT/MONETARY 4, **BIGINT/DOUBLE 8**. 기존 `data_readval/data_writeval` 및 `data_cmpdisk` 를 무수정으로 재사용 가능(assert 최대 4 충족). 8 은 힙 관례(4)보다 보수적이며 `OR_GET_DOUBLE` 캐스트 UB 를 새 포맷에서 제거한다. 비용은 4B→8B 타입 전환 지점당 ≤4B.
- 이유: §1.2, §1.4, §3. 대안(모두 4): 안전하나 UB 잔존. 롤백: `alignby` 테이블 값만 바꾸면 되므로 포맷 상수 한 줄 변경.

**D-183-2 가변 값:** "정렬하지 않음, 길이 헤더로만 판별". PG 피크 트릭은 채택하지 않음(우리 규칙에서 항상 동일 분기 → 죽은 코드 + 불필요한 불변식 2개). 1B/4B 헤더 판별은 첫 바이트 플래그 비트(예: bit7=0 → 1B 길이 0..127, bit7=1 → 4B 네트워크 오더 길이 & 0x7FFFFFFF, memcpy 로 읽기). 빈 문자열 헤더 0x00 허용(피크가 없으므로 0 금지 불필요).
- 이유: §4.1-4.2. 대안(PG 트릭 유지): 이점 없음. 롤백: 헤더 판별 함수 하나에 국한.

**D-183-3 가변 값 기록 경로:** `data_writeval` 을 비정렬 위치에 호출 금지. `index_*` 계열 또는 접근자 API 내 직접 복사 사용, `data_lengthval` 대신 `index_lengthval`(CHAR_ALIGNMENT) 로 크기 계산. 접근자에 `assert` 로 "기록 크기 == 계산 크기" 명문화.
- 이유: §4.3. 이것을 놓치면 튜플 길이 불일치가 릴리스 빌드에서 조용히 데이터를 깨뜨린다.

**D-183-4 바이트 오더:** 값 바이트 인코딩은 기존 `data_*`(네트워크 오더) 유지. `index_*` 의 호스트 오더는 CS 모드 클라이언트(`cursor.c`)가 같은 바이트를 읽는 구조상 채택하지 않음(AIX PPC 빌드 분기 `CMakeLists.txt:642-647` 존재). 향후 성능 이슈로 분리 검토 가능.

**D-183-5 튜플/값 영역 시작 정렬:** 값 영역 시작은 최소 4B(권고 8B) 정렬을 불변식으로 유지(§2 항목 6). 헤더 4B(정방향 전용 리스트) 뒤에 BIGINT 가 오면 4B 패딩이 생기는 점은 포맷 명세 티켓에서 헤더 크기 결정 시 고려.

---

## 6. 부록 — 놀란 점 / 지도 반영 후보

- 8바이트 타입에 대해 CUBRID 가 계약으로 요구하는 정렬은 4 였다(힙도 4). "자연 정렬 8" 은 CUBRID 기준으로는 *강화*다.
- `OR_GET_FLOAT/OR_GET_DOUBLE` 은 PUT(memcpy)와 GET(캐스트)이 비대칭 — 새 접근자에서 memcpy 로 통일할 기회.
- `COPYMEM` 이 x86 에서만 캐스트, 그 외 memcpy 인 것은 코드베이스가 x86 비정렬 허용에 *의도적으로* 의존한다는 명시적 흔적.
- 문자열 `data_writeval` 의 절대 주소 기반 패딩(§4.3)은 지도의 "가변 값은 정렬하지 않음" 결정과 직접 충돌하는 잠복 계약 — 포맷 명세/접근자 API 티켓의 필수 체크 항목.
