# R8 — 10.2·11.0·11.1·11.2·11.3 → develop 온디스크 차이 전수와 쌍별 처리 등급 예측 (#513, map #472)

기준 브랜치 끝(엔진 `~/dev/cubrid-worktree/develop`, 읽기 전용):
- develop = `5b1867174`
- 10.2 = `origin/release/10.2@416bb667c`, 11.0 = `@44ea22369`, 11.1 = `@e0e4f7a84`, 11.2 = `@baf1d297d`, 11.3 = `@8acbed10e`, 11.4 = `@46212adcd`

표기:
- `파일:줄@<선>`에서 `<선>`은 위 브랜치 끝을 뜻한다. dev는 develop이다.
- 구조체 비교는 정의 블록의 공백을 정규화한 뒤 해시를 비교했다. 스크래치 `.git_ignored_dir/scratch/map472-pairs/513/st/`에 버전별 추출본이 있다.
- 오프셋 교차 확인은 release install의 `libcubrid.so`에서 gdb `ptype /o`로 했다. 대상은 10.2.18.9024, 11.0.16.0419, 11.2.9.0866, 11.3.6.1321, 11.4.6.1963이다. 11.1 install은 없어서 11.1은 소스 비교만 했다.
- 계산으로만 얻은 값에는 "(계산)"을 붙였다.
- 각 줄의 첫 GA 태그(v10.2, v11.0, v11.1, v11.2, v11.3)와 브랜치 끝을 비교했다. 볼륨 헤더, 로그 헤더, BOOT_DB_PARM, HEAP_HDR_STATS, FILEIO 예약 영역, FILE_HEADER, SPAGE_HEADER, 문자열 압축 writer, 클래스 객체 writer가 모두 같았다. 따라서 줄 안의 패치 릴리스는 같은 열로 본다.

11.4→develop 차이(R1~R7 문서, #474 리드 코멘트)는 모든 옛 버전에도 그대로 적용된다. 이 문서는 그 위에 **옛 버전만 추가로 갖는 차이**를 더한다.

## 1. 결론

1. 디스크 호환 레벨은 10.2 = 10.15f, 11.0·11.1 = 11.0f, 11.2·11.3 = 11.2f, 11.4 = 11.4f, develop = 11.5f이다 (release_string.c:102@10.2, :101@11.0, :103@11.1/11.2/11.3, :105@11.4/dev).
   - 상향 커밋: `37720d8ed` #2495 (CBRD-23789, 10.15f→11.0f), `5b4853145` #3506 (CBRD-24255, 11.0f→11.2f), `4e501e5fc` #4802 (CBRD-25088, 11.2f→11.4f), `ecb0915e4` #6706 (11.4f→11.5f).
   - 같은 float 값이 두 줄을 덮는 경우가 있다. 11.0f는 11.0과 11.1이고, 11.2f는 11.2와 11.3이다.
2. **어느 버전에서나 바이트가 같은 것**(10.2..11.4 = develop):
   - FILEIO 워터마크, `PAGE_TYPE` 값, `SPAGE_HEADER`/`SPAGE_SLOT`
   - `HEAP_CHAIN`과 vacuum 플래그, `HEAP_HDR_STATS`(296B, gdb)
   - `FILE_HEADER`(216B, gdb), 파일 테이블(`FILE_EXTENSIBLE_DATA`, `FILE_PARTIAL_SECTOR`), 트래커 항목, 섹터 테이블 상수
   - 오버플로 페이지, vacuum data/dropped files 페이지, ehash 헤더, 카탈로그 페이지 헤더와 repr item
   - OR 레코드/MVCC 헤더 상수, `PR_TYPE` 표(39개 타입의 variable_p/disksize/align), `DB_TYPE` 번호
   - 따라서 11.4용 힙 헤더 transform, FILE_HEADER patch, vacuum 잔여 patch 규칙은 옛 버전에 그대로 쓸 수 있다.
3. **10.2만의 차이 ①: 문자열 압축이 LZO1X다.** 11.0부터는 LZ4다 (CBRD-23703 `ecaa13201` #2391).
   - 헤더 형식 `[0xFF][압축길이 BE i32][원길이 BE i32][payload]`는 같고 payload 알고리즘만 다르다.
   - develop에는 LZO 디코더가 없다.
   - 10.2는 `enable_string_compression` 기본값이 true다 (system_parameter.c:2123@10.2). 그래서 255B 이상인 VARCHAR/VARNCHAR 값은 대부분 LZO로 저장돼 있다. 사용자 레코드, 오버플로 레코드, 클래스 객체 문자열, 카탈로그 행 모두 해당한다.
   - **10.2의 문자열 보유 클래스는 재인코딩 대상**이다.
4. **10.2만의 차이 ②: TDE 이전 형식이다** (CBRD-23608 `0cf60dd26`, 11.0에 포함).
   - FILEIO 예약 영역에서 `pflag`와 `tde_nonce` 자리는 `pflag_reserve_1`과 `p_reserve_3`이다. 10.2는 이 자리에 늘 0을 쓰므로 develop이 "암호화 안 됨"으로 읽는다. 따라서 **그대로** 둔다.
   - `BOOT_DB_PARM`에는 `tde_keyinfo_hfid`가 없다(124B→136B).
   - 클래스 객체 고정 영역에는 `tde_algorithm`이 없다(84B→88B).
   - 로그 페이지 헤더의 `flags` 자리는 `dummy1`이다.
   - keyinfo 힙과 `<db>_keys`를 새로 만드는 일은 R9(#510)의 범위다.
5. **10.2만의 차이 ③: 영속 XASL 스트림의 enum 번호가 다르다.** develop 재매핑 앞에 단계가 하나 더 붙는다.
   - `T_CAST_WRAP`가 113에 끼어들었다 (`4cc334318` #2460). 10.2의 opcode가 113 이상이면 +1을 한 뒤 R7의 11.4→develop 식을 적용한다.
   - `FUNC_CODE`에서는 `F_REGEXP_*` 5개가 `F_BENCHMARK` 앞에 끼어들었다 (`20c01592a` #1741 등). `F_BENCHMARK` 이후 코드는 +5다.
6. **11.4만 가진 형식(10.2..11.3 출발에 공통인 차이)**. 모두 11.4f 상향(2023-11-23) **뒤에** 레벨 상향 없이 들어왔다.
   - 볼륨 헤더와 로그 헤더에 `vol_creation` INT64가 추가됐다 (CBRD-25365 `44c022c31` #5719). 볼륨 헤더는 128→136B이고 `chkpt_lsa`부터 8B 밀린다. 로그 헤더는 376→384B이고 `db_compatibility`가 +56에서 +64로 옮겼다(gdb).
   - `db_authorization.grants` 원소가 3-튜플에서 4-튜플(`type` 추가)로 바뀌었다 (CBRD-25184 `1ea4a86e0` #5438).
   - `_db_stored_procedure`/`_args`가 재설계되고 `_db_stored_procedure_code`가 신설됐다 (같은 커밋, `45e44fb21` #5858).
   - `db_serial.att_name`이 `attr_name`으로 바뀌었다 (CBRD-25356 `b85c07b27` #5346).
   - 카탈로그 `DISK_ATTR`에 ndv가 추가돼 80→88B가 됐다 (CBRD-24044 `e05227521` #4768).
   - B-tree 노드 헤더에 `common_prefix`가 추가됐다 (CBRD-25082 `c1e7266a3` #4789).
   - 11.4 GA 태그 `v11.4`가 위 커밋을 모두 포함하므로 11.4 안에서는 갈라지지 않는다.
7. **11.2에서 들어온 user schema** (CBRD-23844 `14742376f` #3488, `0139ad69c` #3494)는 레코드 **레이아웃**을 바꾸지 않았다. 바뀐 것은 다음 둘이다.
   - 클래스 객체의 이름 **값**이 `owner.name`이 됐다.
   - `_db_class`, `db_serial`, `db_trigger`에 `unique_name` 칼럼이 생겼고, `_db_synonym`(`540916ef6` #3541)과 `_db_server`(`26ab1aab6` #3183)가 신설됐다.
   - 세부는 R10(#511)으로 넘긴다.
8. **레벨 상향 없이 들어온 이미지 변경**(위 6 말고): 11.3이 DEDUPLICATE를 넣었다 (CBRD-24478 `7add5356d` #4401). 인덱스 제약에 의사 속성(id 기준 `0x8A8B8C90`, deduplicate_key.h:51@11.3)이 붙고 B-tree 루트 헤더가 비트필드가 됐다. 레벨은 11.2f 그대로다.
   - 그래서 11.2f라는 값만으로는 11.2와 11.3을 가를 수 없다. `db_release` 문자열(로그 헤더 +40, 15B)로 가른다.
   - 11.4는 이미 같은 의사 속성을 처리한다(R3). 11.3 출발에도 그 처리를 켜면 된다.
9. **11.1은 자기 열이 필요 없다.** 레벨 11.0f, 모든 구조체 해시, ORC enum, 카탈로그 칼럼 집합, `OPERATOR_TYPE`, 클래스 객체 writer가 11.0과 같다. 차이는 CDC 로그 레코드와 읽기 쪽 코드뿐이다. 11.0 열이 11.1을 덮는다.
10. **판정.** 다섯 출발 모두 기본 등급은 11.4와 같은 "clone/copy + patch, 힙 헤더 transform, 카탈로그 재생성, B-tree 재빌드"다. 옛 버전에 더해지는 것은 다음과 같다.
    - 공통(10.2..11.3): 볼륨마다 page 0 transform. 로그 헤더 디코더. same-slot 행 transform(grants, SP, serial).
    - 10.2: 문자열 보유 클래스의 레코드 transform(LZO→LZ4 또는 비압축), BOOT_DB_PARM transform과 keyinfo 신설, 클래스 객체 84B 디코더, 스트림 enum 2단 재매핑.
    - 전 페이지 transform이 필요한 쌍은 없다. 다만 10.2에서 문자열이 많은 DB는 재인코딩 클래스 비율이 높아 clone의 이점이 줄어든다.

## 2. 항목별 표

열 머리: **10.2 | 11.0 (=11.1) | 11.2 | 11.3 | 11.4 | develop**. "=11.4"는 11.4와 바이트가 같다는 뜻이다.

### 2.1 디스크 호환 레벨과 레벨 상향 없이 들어온 이미지 변경

| 항목 | 10.2 | 11.0 | 11.2 | 11.3 | 11.4 | develop | 커밋 / PR |
|---|---|---|---|---|---|---|---|
| `disk_compatibility_level` | 10.15f | 11.0f | 11.2f | 11.2f | 11.4f | 11.5f | `d81b071e8` #1187 (10.13→10.15), `37720d8ed` #2495, `5b4853145` #3506, `4e501e5fc` #4802, `ecb0915e4` #6706 |
| `disk_compatibility_rules[]` | 빈 표 | 빈 표 | 빈 표 | 빈 표 | 빈 표 | 빈 표 | release_string.c:274@10.2, :270@11.2, :272@11.4 |
| 상향 없이 들어온 변경 | — | — | — | DEDUPLICATE (`7add5356d` #4401) | vol_creation (`44c022c31` #5719), grants/SP (`1ea4a86e0` #5438), serial attr_name (`b85c07b27` #5346), DISK_ATTR ndv (`e05227521` #4768, 상향 64분 뒤), BT common_prefix (`c1e7266a3` #4789), log `cdc_arv_num_to_keep` (`6186f8cca` #7790, dummy 재사용, v11.4.6부터) | R1 §2.1 | 커밋 시각은 `git log --format=%ci` |

### 2.2 `FILEIO_PAGE` 예약 영역 (모든 페이지 +0..31)

| off | 10.2 | 11.0..11.4 = develop | 커밋 |
|---|---|---|---|
| 0..14 | lsa, pageid, volid, ptype | 같음 | — |
| 15 | `pflag_reserve_1` (file_io.h:182@10.2) | `pflag` (AES 0x1, ARIA 0x2; file_io.h:179@11.0) | `0cf60dd26` CBRD-23608 |
| 16, 20 | `p_reserve_1`, `p_reserve_2` | 같음 | — |
| 24 | `p_reserve_3` INT64 (:185@10.2) | `tde_nonce` (:182@11.0) | `0cf60dd26` |
| IO−8 | 워터마크 lsa | 같음 (해시 동일) | `d81b071e8` #1187 (10.2에 이미 있음) |

10.2는 `fileio_initialize_res`에서 15와 24를 0으로 쓴다 (file_io.c:11612, 11615@10.2). DWB도 같은 값을 assert한다 (double_write_buffer.c:2595-2597@10.2). 그래서 develop은 10.2 페이지를 "pflag=0, 평문"으로 읽는다. **그대로** 둔다. 11.0..11.3에서 `pflag≠0`인 페이지는 TDE이고 R9 범위다.

### 2.3 볼륨 헤더 (각 볼륨 page 0, 사용자 영역 +0)

10.2..11.3은 구조체 해시가 같다(disk_manager.c:75@10.2, :74@11.3). gdb로 128B임을 확인했다. 11.4와 develop은 136B다.

| 필드 | 10.2..11.3 off | 11.4 = develop off | 처리 |
|---|---|---|---|
| magic..sys_lastpage, dummy2 | 0..71 | 0..71 | 복사 |
| `db_creation` | 72 | 72 | 새 로그 값으로 (R1 R7) |
| `vol_creation` | — | 80 | **신설**. 출발 `db_creation` 또는 이전 시각 (disk_manager.c:96@11.4) |
| `chkpt_lsa` | 80 | 88 | 새 로그 값 |
| `boot_hfid` | 88 | 96 | 복사 |
| `reserved0..3` | 100..115 | 108..123 | 복사 |
| `next_volid`, var 오프셋 3개 | 116..123 | 124..131 | 복사 (오프셋은 `var_fields` 기준 상대값이라 값은 그대로, disk_manager.c:644@dev) |
| `var_fields` (경로·remarks 문자열) | 124.. | 132.. | 8B 뒤로 밀어 다시 쓴다 |

커밋: CBRD-25365 `44c022c31` #5719 (2024-12-17, 11.4에 포함, develop에도 같은 정의 disk_manager.c:95@dev). 결과: 10.2..11.3 출발은 **볼륨마다 page 0 transform**이다(한 장). 11.4 출발은 patch다.

### 2.4 파일 관리자: `FILE_HEADER`, 파일 테이블, 섹터 테이블, 트래커

| 항목 | 10.2..11.4 | develop | 근거 |
|---|---|---|---|
| `FILE_HEADER` | 216B, 구조체 해시 동일 (file_manager.c:84@10.2, :91@11.4; gdb 216B 5개 install) | 200B | R1 §2.7. 처리는 11.4와 같은 patch(사용자 영역 184..199를 0으로) |
| `FILE_EXTENSIBLE_DATA`, `FILE_PARTIAL_SECTOR`, 트래커 heap 메타 | 해시 동일 | 같음 (`file_partial_sector`가 .h로 이동만) | file_manager.c:220@10.2, file_manager.h:162@dev |
| `FILE_TYPE` enum | 동일 | 동일 | file_manager.h:40 |
| `FILE_FLAG_*` | 10.2: 0x1, 0x2 | 11.0+: + `ENCRYPTED_AES 0x4`, `ENCRYPTED_ARIA 0x8` | `0cf60dd26`. 10.2 파일은 0x4/0x8이 0이므로 그대로 |
| 섹터 테이블 상수 (`DISK_STAB_*`, `DISK_SECTOR_NPAGES` 64) | 해시 동일 | 동일 | disk_manager.c `#define DISK_*` 비교 |

### 2.5 `BOOT_DB_PARM` (boot 힙 레코드)

| 항목 | 10.2 | 11.0 | 11.2 | 11.3..develop | 커밋 |
|---|---|---|---|---|---|
| 크기 (gdb) | 124B | 136B | 136B | 136B | |
| `tde_keyinfo_hfid` @124 | 없음 (boot_sr.c:107-127@10.2) | 있음 (:129@11.0) | 있음 | 있음 | `0cf60dd26` |
| `#if 1 classname_table` | 있음 | 있음 | 있음 | 매크로만 제거, 레이아웃 동일 | — |

10.2 출발의 처리 순서:
1. 레코드를 136B로 늘린다(transform).
2. keyinfo 힙(레코드 1개 `TDE_KEYINFO`)과 `<db>_keys`를 새로 만든다. develop은 재시작할 때 `tde_cipher_initialize(&boot_Db_parm->tde_keyinfo_hfid)`를 부른다(boot_sr.c:2330@dev). keyinfo가 없는 DB는 develop이 열 수 없다고 예측한다[VERIFY]. 생성 규칙(`tde_initialize`, tde.c:111-229@dev)은 R9 범위다.

### 2.6 힙 페이지 (`HEAP_HDR_STATS`, `HEAP_CHAIN`, slotted page, 오버플로)

| 항목 | 10.2..11.4 | develop | 처리 |
|---|---|---|---|
| `HEAP_HDR_STATS` | 296B, 해시 동일 (heap_file.c:191@10.2, gdb 5개) | 1152B | 11.4와 같은 transform (R1 R5) |
| `HEAP_CHAIN` | 40B, 해시 동일 (heap_file.c:270@10.2) | 플래그 비트 추가 | 그대로 |
| vacuum 플래그 매크로 | 동일 (heap_file.c:240-242@10.2) | 동일 | patch 대상 판정 규칙을 그대로 쓴다 |
| `SPAGE_HEADER` | 32B. 11.3에서 주석만 바뀜 (slotted_page.h:62@10.2) | `need_update_best_hint` 삭제 | 11.4와 같음 (권장 patch) |
| `SPAGE_SLOT` | 동일 | 동일 | 그대로 |
| 오버플로 페이지 | `OVERFLOW_FIRST_PART`/`REST_PART`는 10.2·11.0에서 .c에 있다가 11.1부터 .h로 옮겼다. 레이아웃 동일 (overflow_file.c:44-57@10.2) | 동일 | 그대로. 다만 레코드가 재인코딩 클래스 것이면 다시 쓴다 |
| BIGONE 임계값 | `spage_max_record_size − 296` (헤더 크기 동일이라 11.4와 같음) | R2 §1.9 | — |

### 2.7 OR 레코드 / MVCC 헤더

`object_representation_constants.h`의 `OR_*MVCC*`, `OR_*OFFSET*`, `OR_*BOUND*`, `OR_*HEADER*`, `OR_*CHN*`, `OR_*REPID*` 정의 집합을 버전마다 비교했다. 10.2..11.3은 같고, 11.4에서만 `OR_MAX_BYTE_UNSIGNED`/`OR_MULTI_MAX_OFFSET`(MIDXKEY 헤더용, B-tree 범위)이 추가됐다. 레코드 헤더, 가변 오프셋 표, bound bit 규칙은 **10.2부터 develop까지 같다**. `object_representation.c`의 함수 단위 비교 결과는 다음과 같다.
- 10.2→11.0: `or_put_varchar_internal`만 바뀌었다(LZO→LZ4).
- 11.2→11.3: put/get 함수가 헤더 inline으로 옮겨졌다(CBRD-24632 `ffb8a3819` #4066, 리팩터).
- 그 밖에는 리스트파일·메서드 시그니처 직렬화(영속되지 않음)뿐이다.

### 2.8 타입별 값 인코더 (`object_primitive.c`)

비교 방법: 함수 단위로 나눠 공백을 정규화한 뒤 비교했다. 대상은 `*writeval*`, `*readval*`, `*lengthval*`, `*compress*`, `pr_write_*`, `pr_get_size*`, `*cmpdisk*`다.

| 타입 / 함수 | 10.2 | 11.0 | 11.1 | 11.2 | 11.3 | 11.4 | develop |
|---|---|---|---|---|---|---|---|
| `PR_TYPE` 표 (39개) | 11.4와 동일 | 동일 | 동일 | 동일 | 동일 | 기준 | R2 (CHAR/NUMERIC variable_p 변경 등) |
| VARCHAR/VARNCHAR 압축 payload | **LZO1X** (`lzo1x_decompress` object_primitive.c:10820, 13854, 15928@10.2; 압축은 object_representation.c:890@10.2) | **LZ4** (`LZ4_decompress_safe` :10825, 15998@11.0) | LZ4 | LZ4 | LZ4 | LZ4 | LZ4 (CHAR도 LZ4, R2) |
| 압축 헤더 `0xFF, BE i32 압축길이, BE i32 원길이` | 같음 (`pr_write_compressed_string_to_buffer` :16203@10.2) | 같음 | 같음 | 같음 | 같음 | 같음 | 같음 |
| 압축 임계 `OR_MINIMUM_STRING_LENGTH_FOR_COMPRESSION` | 255 (object_representation.h:1418@10.2) | 255 | 255 | 255 | 255 | 255 | 255 |
| `mr_writeval_string_internal` | — | — | — | — | — | 빈 문자열을 명시적으로 처리 | 변경. 길이 0 문자열의 바이트는 같다(계산: 둘 다 `[0x00]` 길이 바이트 + 패딩) |
| 그 밖의 writer (CHAR, NUMERIC, BIT, JSON, SET, ENUM, 날짜시간, OID, ELO) | 11.4와 동일 | 동일 | 동일 | 동일 | 동일 | 기준 | R2 (CHAR/NUMERIC/NCHAR만 변경) |
| reader 차이 (varbit NULL, resultset, data_readval_string 백포트) | — | 읽기 경로 | 읽기 경로 | 읽기 경로 | — | — | 바이트 영향 없음 |

압축 커밋: CBRD-23703 `ecaa13201` #2391 (2020-09-01, 11.0 상향 전). 10.2 압축 경로는 `mr_writeval_string_internal`, `mr_writeval_varnchar_internal`, `or_put_varchar_internal`(클래스 객체와 카탈로그 문자열)이다. `DB_TYPE` 번호(0..40)는 10.2..11.4가 같다.

비교 연산의 의미도 바뀌었다. 바이트가 아니라 B-tree 재빌드와 파티션에만 영향이 있다.
- CBRD-23731(`b6873b9b9` #2476, `288efc55b` #2483)과 CBRD-24149(`8e8ec6918` #3339 @11.0 줄, `991c8a4bc` #3283 @11.2 줄)가 CHAR/VARCHAR 비교에서 뒤 공백 처리를 바꿨다. 11.0 줄 안에서도 패치 릴리스 사이에 바뀌었다.
- 재빌드는 develop 규칙으로 정렬하므로 바이트 문제는 없다. 남은 질문은 §6에 있다.

### 2.9 클래스 객체 (root 힙, `transform_cl.c`)

| 항목 | 10.2 | 11.0 = 11.1 | 11.2 | 11.3 | 11.4 | develop | 커밋 |
|---|---|---|---|---|---|---|---|
| ORC enum 블록 | `ORC_CLASS_TYPE = 68`이 마지막 (object_representation.h:762@10.2) | + `ORC_CLASS_TDE_ALGORITHM = 84` (:762@11.0) | = 11.0 | = 11.0 | = 11.0 | = 11.0 (R3) | `0cf60dd26` |
| 고정 영역 | 84B (계산: 88 − 4) | 88B | 88B | 88B | 88B | 88B (R3) | `or_put_int (buf, class_->tde_algorithm)` transform_cl.c:3696@11.0 |
| var 필드 수 | 17 | 17 | 17 (11.2 개발 중 `unique_name` var를 넣었다가 `0139ad69c` #3494에서 되돌림) | 17 | 17 | 17 | — |
| 이름 값 (`ORC_NAME_INDEX`) | `name` | `name` | `owner.name` | `owner.name` | `owner.name` | `owner.name` | `14742376f` #3488 → R10 |
| 하위구조 메타(attribute, domain, partition, method, repr…) | 11.4와 동일 (transform.c diff는 tde 두 줄과 정의 이동뿐) | 동일 | 동일 | 동일 | 기준 | R3: partition 4→8B, 제약 꼬리, FK 5원소 | — |
| 제약 property 시퀀스 (`classobj_put_index`) | 11.4와 동일 | 동일 | 동일 | 리팩터만 (바이트 동일) | 기준 | R3 | — |
| 인덱스 의사 속성(DEDUPLICATE) | 없음 | 없음 | 없음 | **있음** | 있음 | 제거 (`#8104`) | `7add5356d` #4401 |
| 문자열 압축 | LZO | LZ4 | LZ4 | LZ4 | LZ4 | LZ4 | §2.8 |

develop 쪽은 어차피 재직렬화(R3 결론 10)한다. 따라서 옛 버전은 **디코더**만 늘리면 된다. 10.2에서는 고정 84B 디코더와 `tde_algorithm = 0`(NONE) 기본값이 필요하다. 10.2..11.1에서는 이름을 한정하는 규칙이 필요하다(R10).

### 2.10 카탈로그 파일 (`DISK_REPR`, `DISK_ATTR`, `CLS_INFO`, BT 통계)

| 항목 | 10.2..11.3 | 11.4 | develop | 커밋 |
|---|---|---|---|---|
| `CATALOG_*_SIZE/OFF` 정의 집합 | 동일 | `DISK_ATTR` 80→88B (`CATALOG_DISK_ATTR_NDV_OFF` 80, system_catalog.c:116-117@11.4; :114@11.3) | BT_STATS V1 120B, CLS_INFO INT64 @32 (R3) | `e05227521` #4768 |
| 페이지 헤더, repr item, catalog key | 동일 | 동일 | 동일 | — |

카탈로그는 클래스 객체에서 재생성하므로(R3) 출발 버전의 카탈로그 바이트는 읽지 않는다. 출발 카탈로그를 읽는 도구가 생기면 `DISK_ATTR` 80B 변형이 필요하다.

### 2.11 `_db_*` 카탈로그 테이블과 vclass

테이블(힙을 가진 시스템 클래스) 수. `catcls_class_install` + `au_install` + `tr_install` 기준이다. `_db_resolution`은 정의만 있고 만들지 않는다.

| | 10.2 | 11.0 = 11.1 | 11.2 = 11.3 | 11.4 | develop (R4) |
|---|---|---|---|---|---|
| 테이블 | 25 | 26 (+`dual`, `f739bed2b` #2365) | 28 (+`_db_synonym` `540916ef6` #3541, +`_db_server` `26ab1aab6` #3183) | 29 (+`_db_stored_procedure_code`) | 30 (R4 §1.1) |
| 시스템 vclass | 18 | 18 | 20 (+`db_server`, `db_synonym`) | 20 | 25 + IS 19 |

fastmig가 행을 그대로 옮기는 same-slot 테이블(`crates/catalog/src/system_classes.rs` `SAME_SLOT`)의 칼럼 차이는 다음과 같다. 칼럼 목록은 boot_cl.c `boot_define_*`(10.2..11.3)와 schema_system_catalog_install.cpp(11.4)에서 뽑았다.

| 테이블 | 10.2 | 11.0 = 11.1 | 11.2 = 11.3 | 11.4 | 커밋 |
|---|---|---|---|---|---|
| `db_root`, `db_user`, `db_password` | = 11.4 | = 11.4 | = 11.4 | 기준 | 칼럼 동일 (authenticate.c `au_install`, authenticate_context.cpp:340-476@11.4) |
| `db_authorization` | 칼럼 = 11.4, **grants 원소 3개** `{class, grantor, cache}` (authenticate.c:131@10.2) | 3개 | 3개 (:132@11.3) | **4개** `{type, class, grantor, cache}` (authenticate_grant.hpp:66-71@11.4) | `1ea4a86e0` #5438. 옛 원소는 `type = DB_OBJECT_CLASS(0)`(dbtype_def.h:492@11.4)을 앞에 붙인다 |
| `db_trigger` | `owner, name, …, comment` | 같음 | + `unique_name` (trigger_manager.c:7370@11.2) | 11.2와 같음 | `14742376f` #3488 → R10 |
| `db_serial` | `name, owner, …, class_name, att_name, cached_num, comment` | 같음 | + `unique_name` (boot_cl.c:3290@11.2), PK `pk_db_serial_unique_name` | `att_name`→**`attr_name`** | `14742376f`, `b85c07b27` #5346 |
| `_db_stored_procedure` | `sp_name, sp_type, return_type, arg_count, args, lang, target(4096), owner, comment` | 같음 | 같음 (boot_cl.c:3089-3135@11.3) | `unique_name, …, pkg_name, is_system_generated, directive, target_class, target_method, …` (install.cpp:829-860@11.4) | `1ea4a86e0` #5438 |
| `_db_stored_procedure_args` | `sp_name, index_of, arg_name, data_type, mode, comment` | 같음 | 같음 | `sp_of`(OID), `is_system_generated`, `default_value`, `is_optional` 추가 (:867-890@11.4) | `1ea4a86e0`, `45e44fb21` #5858 |
| `_db_stored_procedure_code` | 없음 | 없음 | 없음 | 신설 (:901@11.4) | `1ea4a86e0` |
| `_db_synonym`, `_db_server` | 없음 | 없음 | 있음 (11.4와 칼럼 동일) | 기준 | — |
| `db_ha_apply_info` | = 11.4 | = 11.4 | = 11.4 | 기준 | — |

재생성 대상 테이블(derived, R4)의 칼럼 차이는 참고용이다. `_db_class.tde_algorithm`(11.0+)과 `unique_name`(11.2+, 인덱스 `i__db_class_unique_name`)이 생겼다. `_db_auth`에서는 `class_of`가 `object_type, object_of`로 바뀌었다(11.4, `1ea4a86e0`). 그 밖의 derived 테이블 칼럼은 10.2..11.4가 같다.

### 2.12 영속 XASL 스트림 (파티션 식, 필터/함수 인덱스)

| 항목 | 10.2 | 11.0..11.3 | 11.4 | develop | 커밋 |
|---|---|---|---|---|---|
| 노드 writer(`xts_process_regu_variable/arith_type/function_type/pred_expr/eval_term/func_pred/attr_descr/db_value` 등) | 11.4와 동일 | 동일 | 기준 | R7 (동일) | 함수 단위 diff 0 |
| `OPERATOR_TYPE` 개수 | 198 | 199 | 199 | 206 | |
| 10.2→11.0 재매핑 | `T_CAST_WRAP` 삽입 (storage_common.h:803@11.0): **old ≥ 113 → +1** (T_CASE 113→114) | — | — | R7 식 | `4cc334318` #2460 |
| `FUNC_CODE` | `F_REGEXP_COUNT..SUBSTR` 없음 | 5개 삽입 (storage_common.h:930@11.0) → `F_BENCHMARK` 이후 +5 | 같음 | db_function.hpp로 이동, 동일 | `20c01592a` #1741, `3df36a110` #1647 |
| `MISC_OPERAND`, `REL_OP`, `BOOL_OP`, `TYPE_PRED_EXPR` | 동일 | 동일 | 동일 | 동일 | — |
| `REGU_DATATYPE` | 17개 | 17개 | + `TYPE_SP` 끝에 추가 | 같음 | 번호 이동 없음 |
| `DB_DEFAULT_EXPR_TYPE` | 0..12 동일 | 동일 | 동일 | + 13..15 | R7 |
| 상수 문자열 | LZO 가능 | LZ4 | LZ4 | LZ4 | §2.8 |
| 컨테이너 | CHAR | CHAR | CHAR | VARCHAR | R7 |

10.2 출발의 opcode 합성 재매핑(계산):
- 1단계(10.2→11.4): `o11 = o + (o >= 113 ? 1 : 0)`
- 2단계(11.4→develop, R7): `o11 + (o11 >= 184 ? 6 : o11 >= 159 ? 4 : 0)`

`FUNC_CODE`에서 밀리는 것은 `F_BENCHMARK`와 분석함수용 `PT_*` 코드다. 이것들이 파티션·인덱스 식에 나타나는지는 확인하지 않았다(§6 질문 4).

### 2.13 B-tree (재빌드, 참고)

| 항목 | 10.2 | 11.0 | 11.2 | 11.3 | 11.4 | 커밋 |
|---|---|---|---|---|---|---|
| 루트 헤더 | `reverse_reserved` int | 같음 | `_64{over:2,num_oids:10,…}` 비트필드 (btree_load.h:216@11.2) | + `rev_level:16|deduplicate_key_idx:16` (:227@11.3) | 통계 INT64, `_64` 삭제 (:210@11.4) | `7add5356d` #4401 등 |
| 노드 헤더 | 동일 | 동일 | 동일 | 동일 | + `common_prefix` (:202@11.4) | `c1e7266a3` #4789 |
| 오버플로 OID 헤더 | 동일 | 동일 | 동일 | 동일 | 동일 | develop에서 16B (R6) |

모든 쌍에서 B-tree는 develop 형식으로 재빌드하므로 출발 B-tree 디코더는 필요 없다.

### 2.14 로그 헤더와 로그 페이지 (도구가 새로 쓴다, 출발은 읽기만)

10.2..11.3의 `struct log_header`는 해시가 같다(log_storage.hpp:113@11.3). gdb로 10.2와 11.3 모두 376B임을 확인했다.

| 필드 | 10.2..11.3 off (gdb) | 11.4 off | develop off | 비고 |
|---|---|---|---|---|
| magic | 0 | 0 | 0 | |
| +28 | `dummy` | `cdc_arv_num_to_keep` | 같음 | `6186f8cca` #7790 |
| `db_creation` | 32 | 32 | 32 | |
| `vol_creation` | — | 40 | 40 | `44c022c31` #5719 |
| `db_release[15]` | 40 | 48 | 48 | 11.2/11.3 판별에 쓴다 |
| `db_compatibility` | **56** | 64 | 64 | 버전 판별 |
| `db_iopagesize`/`db_logpagesize` | 60/62 | 68/70 | 68/70 | |
| `is_shutdown` | 64 | 72 | 72 | R0 사전 거부 |
| `mvcc_next_id` | 72 | 80 | 80 | |
| `db_charset` | 92 | 100 | 100 | |
| `dummy3/4` | 94/95 | 102/103 | `sysmeta_version` u16 | |
| `fpageid`/`append_lsa`/`chkpt_lsa` | 96/104/112 | 104/112/120 | 같음 | 새 로그 시작점(R1 R4b) |
| `vacuum_last_blockid` | 192 | 200 | 200 | |
| 크기 | 376 | 384 | 384 | |

로그 페이지 헤더(`LOG_HDRPAGE`)는 10.2에서 +10이 `dummy1`이다(log_storage.hpp:55@10.2). 11.0부터 이 자리가 `flags`다(:70@11.0, `0cf60dd26`). 체크섬 대상과 범위는 같다. 다만 CRC 구현이 바뀌었다. 10.2는 gcrypt `GCRY_MD_CRC32` + `htonl`(crypt_opfunc.c:624-650@10.2)이고, 11.0부터는 CRC++ `CRC_32`(:672-676@11.0)다. 둘 다 표준 CRC-32 값을 낸다고 예측한다[VERIFY]. fastmig가 출발 로그 페이지 체크섬을 검사하지 않으면 영향은 없다.

### 2.15 볼륨 밖 파일

| 파일 | 10.2..11.3 | 처리 | 근거 |
|---|---|---|---|
| `_vinf` | `"%4d %s\n"` 동일 (log_page_buffer.c:4497@10.2, :4711@11.4) | 11.4와 같음 (develop 형식으로 새로 씀) | — |
| `databases.txt` | 형식 동일 (databases_file.c diff에 형식 변경 없음) | 11.4와 같음 | — |
| `_dwb` | FILEIO 페이지 배열 (DWB는 10.2부터 있음, `3917201b0` #829) | 옮기지 않음 | R1 R8 |
| `_keys` | 10.2 없음 / 11.0+ 있음 | 10.2: 새로 생성(R9). 11.0+: 11.4와 같음 | `0cf60dd26` |
| LOB 파일 | 로케이터 `file:` 경로 형식 동일. es_posix.c는 디렉터리 해시 음수 처리(`r = abs`)와 mkdir 권한만 다르다 | 11.4와 같은 이동 규칙(#507) | `git diff origin/release/10.2 origin/release/11.4 -- src/storage/es_posix.c` |
| 시간대 데이터 | `timezones/tzdata` 10.2..develop diff 0 (빌드 스크립트만) | `db_root.timezone_checksum` 그대로 | `a48bf96db` #3753 |

### 2.16 범위만 기록하는 항목

- **TDE (R9, #510)**:
  - 11.0..11.3은 `pflag≠0` 페이지, `FILE_FLAG_ENCRYPTED_*`, 클래스 `tde_algorithm`, keyinfo 힙, `_keys`, 로그 페이지 `flags`의 암호화 비트가 11.4와 같은 형식이다(구조체 해시 동일: `TDE_KEYINFO` tde.h:158@11.0 = dev).
  - 10.2는 TDE가 없다. keyinfo 힙과 `_keys`를 새로 만드는 일과 BOOT_DB_PARM 확장만 남는다.
- **user schema (R10, #511)**:
  - 11.2부터 이름 값이 `owner.name`이다. 클래스 객체 이름, classname ehash 키, `_db_class.unique_name`, `db_serial.unique_name`, `db_trigger.unique_name`, `_db_synonym`이 해당한다.
  - 10.2..11.1 출발은 이 값들을 만들어야 한다.
  - 11.4의 SP `unique_name`은 11.2/11.3 출발에도 없다(SP 이름은 11.3까지 전역).
  - 참고: CBRD-26374(`2c2163932`, 11.4)는 "부분 user schema를 지원하는 버전"용 loaddb 호환 옵션을 넣었다. 11.2/11.3의 user schema 범위가 11.4와 다르다는 신호이므로 R10에서 확인한다.

## 3. 쌍별 판정 (페이지 처리 등급 예측)

복사 방식(clone/copy)은 버전과 무관하게 볼륨마다 정한다. 아래 등급은 clone 또는 copy 뒤 제자리에서 가하는 처리다.

| 영역 | 10.2→dev | 11.0/11.1→dev | 11.2→dev | 11.3→dev | (참고) 11.4→dev |
|---|---|---|---|---|---|
| 데이터 볼륨 일반 페이지 FILEIO | 그대로 | 그대로 (pflag≠0이면 R9) | 그대로 (R9) | 그대로 (R9) | 그대로 |
| 볼륨 헤더 page 0 | **transform** | **transform** | **transform** | **transform** | patch |
| 섹터 테이블, 파일 테이블, 트래커 | 그대로 (공간 할당 시 patch) | 같음 | 같음 | 같음 | 같음 |
| 파일 헤더 page | patch | patch | patch | patch | patch |
| boot 힙 (`BOOT_DB_PARM`) | **transform** + keyinfo 힙 신설 | patch | patch | patch | patch |
| 힙 헤더 page | transform | transform | transform | transform | transform |
| 힙 데이터 page | patch/그대로. 재인코딩 클래스 transform. **+ 문자열 보유 클래스(LZO)** | patch/그대로, 재인코딩 클래스 transform | 같음 | 같음 | 같음 |
| 오버플로 page | 그대로. 재인코딩 클래스(LZO 포함) transform | 그대로 / 재인코딩 transform | 같음 | 같음 | 같음 |
| root 힙(클래스 객체) | 재직렬화 (84B 디코더, LZO, 이름 한정) | 재직렬화 (이름 한정) | 재직렬화 | 재직렬화 (DEDUP 제거) | 재직렬화 |
| same-slot 행 (`db_*`, SP, synonym, server) | transform (grants 3→4, serial 두 칼럼, trigger unique_name, SP 재구성, synonym/server/code 빈 테이블) | 같음 | transform (grants, serial attr_name, SP) | 11.2와 같음 | 11.4 규칙(R4) |
| derived 카탈로그 테이블, 카탈로그 파일, vclass | 재생성 | 재생성 | 재생성 | 재생성 | 재생성 |
| 파티션 식 스트림 | transform (2단 재매핑, LZO 상수) | transform (R7 식) | transform | transform | transform |
| B-tree | 재빌드 | 재빌드 | 재빌드 | 재빌드 | 재빌드 |
| 로그 | 새로 생성 (376B 헤더 디코드) | 같음 | 같음 | 같음 | 새로 생성 |
| DWB | 옮기지 않음 | 같음 | 같음 | 같음 | 같음 |

판정 요지:
- **11.0/11.1·11.2·11.3**: 11.4 경로에 다음 셋을 더하면 된다. 볼륨 page 0 transform(볼륨당 1장), 로그 헤더 디코더, same-slot 행 매퍼. 사용자 힙 페이지의 등급은 11.4와 같다. 11.2와 11.3의 차이는 DEDUPLICATE 의사 속성 하나다(11.4와 같은 처리).
- **10.2**: 위에 다음이 더해진다. LZO 문자열 재인코딩(문자열 칼럼이 있는 클래스의 레코드 전부를 읽어야 한다), BOOT_DB_PARM과 keyinfo(R9), 클래스 객체 84B, 스트림 2단 재매핑, 이름 한정(R10). 재인코딩 클래스 비율이 높으면 clone으로 공유되는 페이지가 줄어든다. 그래서 문자열 위주 DB에서는 copy 중 인라인 처리가 더 나을 수 있다(측정 필요).

## 4. fastmig 11.4 코덱에 더해야 할 디코더와 매퍼

현재 코덱은 `crates/ondisk/src/version_line.rs`의 `VersionLine::{V11_4, Develop}` 둘만 안다.

| # | 대상 | 필요한 출발 | 위치(현재 코덱) | 내용 |
|---|---|---|---|---|
| D1 | 버전 판별 | 전부 | `version_line.rs` `from_db_compatibility` | `db_compatibility`를 +64에서 읽을지 +56에서 읽을지 정한다. 둘 다 읽어 {10.15, 11.0, 11.2}이면 옛 레이아웃이다. 11.2f는 `db_release`(+40)로 11.2와 11.3을 가른다. 새 선은 `V10_2`, `V11_0`(11.1 포함), `V11_2`(11.3은 DEDUP 플래그로 구분) |
| D2 | 로그 헤더 376B 디코더 | 10.2..11.3 | `log_header.rs` (`off::*`는 11.4 고정) | §2.14 오프셋 표 |
| D3 | 볼륨 헤더 128B 디코더 → develop 136B 인코더 | 10.2..11.3 | `volume_header.rs` (`off::VOL_CREATION` 80 고정) | `vol_creation` 채우기, var_fields 8B 이동 |
| D4 | `BOOT_DB_PARM` 124B | 10.2 | `boot_parm.rs` (`BOOT_DB_PARM_SIZE` 136) | 136B로 확장. keyinfo 힙과 `_keys` 생성은 R9 |
| D5 | **LZO1X 해제기** | 10.2 | `value/string.rs` (`lz4_flex`만) | `[0xFF][clen][len]` payload를 LZO1X로 푼다. 재기록은 LZ4 또는 비압축(compressed_len=0). 사용자 레코드, 오버플로, 클래스 객체, same-slot 행, 스트림 상수에 공통으로 쓴다 |
| D6 | 재인코딩 클래스 분류 확장 | 10.2 | `catalog/src/classify.rs` | VARCHAR/VARNCHAR/STRING 속성 또는 그런 원소 도메인의 컬렉션이 어느 repr에든 있으면 재인코딩 후보로 둔다. 레코드 단위로 0xFF 압축 문자열이 실제로 있는지 보고 transform 여부를 정할지는 §6 질문 1 |
| D7 | 클래스 객체 고정 84B | 10.2 | `class_object/class_record.rs` (88B 고정) | `tde_algorithm`이 없으면 0으로 둔다 |
| D8 | same-slot 행 매퍼 | 10.2..11.3 | `catalog/src/same_slot_rows.rs`, `system_classes.rs` | grants 3→4 원소, `db_serial`(`att_name`→`attr_name`, ≤11.1은 `unique_name` 생성), `db_trigger.unique_name`(≤11.1), SP 행 재구성(`target`→`target_class`/`target_method`, args `sp_name`→`sp_of` OID, `unique_name`), 없는 테이블은 빈 테이블로 처리(`dual` 10.2, synonym/server ≤11.1, SP code ≤11.3) |
| D9 | 시스템 클래스 이름 집합 | 10.2..11.3 | `system_classes.rs` (11.4 이름 기준) | 버전별 테이블 25/26/28/29, vclass 18/18/20/20 |
| D10 | 스트림 enum 재매핑 1단 | 10.2 | R7 트랜스코더 | `OPERATOR_TYPE` ≥113 +1, `FUNC_CODE` ≥`F_BENCHMARK` +5 |
| D11 | 로그 페이지 헤더 `dummy1` | 10.2 | `log_page.rs` | 읽기만 한다. flags를 0으로 간주 |

필요 없는 것: 출발 B-tree 디코더(재빌드), 출발 카탈로그 파일 디코더(재생성; 읽는다면 `DISK_ATTR` 80B 변형), 힙 헤더·체인·슬롯·MVCC·FILE_HEADER의 버전별 변형(전부 11.4와 동일).

## 5. 11.1 열 여부

11.1은 **11.0 열에 합친다.** 근거:
- `disk_compatibility_level` 11.0f로 같다(release_string.c:103@11.1).
- 비교한 구조체가 모두 같은 해시다: 볼륨 헤더, 로그 헤더, BOOT_DB_PARM, FILEIO 예약, FILE_HEADER, HEAP_HDR_STATS, HEAP_CHAIN, SPAGE, 카탈로그, vacuum, ehash.
- ORC enum, `OPERATOR_TYPE`, catalog 칼럼 추출본, 시스템 클래스 이름 집합이 11.0과 같다(`diff` 0).
- `transform*.c`와 `class_object.c`의 diff는 행위 코드뿐이다(인덱스 매칭, `load_index_from_heap`).
- `object_primitive.c`의 차이는 읽기 경로뿐이다. `data_readval_string` 백포트(CBRD-25905)가 11.0/11.2 줄에만 있고, varbit reader가 다르다.
- 11.1만의 기능은 CDC(CBRD-23842 `d0ed5d000`)다. 공급 로그 레코드는 로그에만 있고, 로그는 새로 쓴다.

## 6. 남은 질문

### 티켓으로 만들 수 있는 질문

1. **[task] 10.2 LZO 문자열 재인코딩의 범위와 구현.**
   - Rust LZO1X 해제기를 정한다: 의존 크레이트를 쓸지, 직접 구현할지.
   - 재기록 형식을 정한다: LZ4 재압축 또는 비압축.
   - transform 대상의 단위를 정한다: (a) 문자열 속성이 있는 클래스 전부, (b) 실제 LZO 값이 든 레코드나 페이지만.
   - T4(#512) 10.2 DB의 255B 이상 VARCHAR와 컬렉션, 클래스 객체 긴 문자열(뷰 spec, 코멘트)로 develop에서 읽히는지 확인한다.
2. **[research] ≤11.3 same-slot 행 매핑의 정답 출처.**
   - 11.4에는 11.3 DB를 올리는 공식 경로(migrate 유틸리티나 upgradedb)가 있다. 그 경로가 grants 4-튜플의 `type`, SP `target` 분리 규칙, `sp_of` 연결, `att_name`→`attr_name`을 어떻게 채우는지 읽어서 D8 매핑을 확정한다.
3. **[task] VersionLine 확장과 버전 판별 규칙.**
   - D1을 구현한다. 11.2f에서 `db_release`로 11.2와 11.3을 가르는 규칙을 고정한다.
   - 10.15f/11.0f/11.2f가 아닌 값은 거부한다.
   - T4 DB 넷의 `_lgat` 헤더 오프셋(§2.14)을 실측해 gdb 값과 대조한다.
4. **[research] 10.2 파티션 스트림 2단 재매핑의 실재 범위.**
   - 10.2의 파티션 식이 허용하는 연산자 가운데 113 이상인 것을 전수로 찾는다(`pt_find_partition_column_count`@10.2).
   - `FUNC_CODE` 중 `F_BENCHMARK` 이후 코드가 스트림에 나타날 수 있는지 확인한다.
   - T4 10.2 DB에 해당 식(예: `HASH(ASCII(c))`)을 넣어 develop pruning 일치를 검증한다.
5. **[research] 문자열 비교 규칙 변경(CBRD-23731, CBRD-24149)의 마이그레이션 영향.**
   - 10.2와 11.0 초기 패치는 뒤 공백 비교 규칙이 develop과 다르다.
   - 이 차이가 유니크 인덱스 재빌드에서 중복을 만들 수 있는지(옛 규칙에서 다르다고 본 두 값을 develop이 같다고 보는 경우), 그리고 CHAR/VARCHAR 키 HASH 파티션 배치에 영향을 주는지 확인한다(R7 Open Q1의 문자열판).

### 아직 흐릿한 것 (지도 Not yet specified 후보)

- 10.2 출발에서 develop이 keyinfo 없는 DB를 실제로 거부하는가. 거부한다면 도구가 TDE 키를 만들려면 암호 라이브러리 의존이 생긴다(R9와 겹친다).
- 10.2 로그 페이지 CRC(gcrypt)와 11.0+ CRC++가 같은 값을 내는가. 출발 로그 체크섬을 검사할 때만 의미가 있다.
- `_db_server.password` 저장 형식(암호화 방식)이 11.2→develop에서 같은가. 이 문서는 칼럼 이름만 비교했다.
- `_db_collation`/`_db_charset` 정적 행이 10.2..11.3과 develop에서 같은 집합인가(FROM_SOURCE 경로). 매크로 칼럼 이름만 같음을 확인했다.
- 11.2/11.3의 "부분 user schema"(CBRD-26374)가 정확히 어디까지인가(R10).
- 10.2 문자열 위주 DB에서 재인코딩 비율에 따른 clone 대 copy-인라인 선택 기준(측정 필요).

## 7. Sources

- 레벨: `src/base/release_string.c:102@10.2, :101@11.0, :103@11.1/11.2/11.3, :105@11.4/dev`. 커밋 `37720d8ed` #2495, `5b4853145` #3506, `4e501e5fc` #4802, `ecb0915e4` #6706, `d81b071e8` #1187.
- 페이지/볼륨:
  - `src/storage/file_io.h:175-186@10.2, :172-183@11.0`, `file_io.c:11612-11615@10.2`
  - `src/storage/disk_manager.c:75@10.2, :74@11.3 (db_creation :92, chkpt_lsa :94), :76-112@11.4 (vol_creation :96)`, `disk_manager.c:644@dev`
  - 커밋 `44c022c31` #5719, `0cf60dd26` (CBRD-23608)
- 파일/부트: `src/storage/file_manager.c:84@10.2, :91@11.4`, `file_manager.h:162@dev`, `src/transaction/boot_sr.c:107-127@10.2, :109-130@11.0`, `boot_sr.c:2330, 5033, 5159@dev`, `src/storage/tde.c:111-229@dev`.
- 힙: `src/storage/heap_file.c:191, 240-242, 270@10.2`, `src/storage/slotted_page.h:62@10.2`, `src/storage/overflow_file.c:44-57@10.2`, `overflow_file.h:38@11.1`.
- 값 인코딩:
  - `src/object/object_primitive.c:10820, 13854, 15928, 16203@10.2`, `:10825, 15998, 16053@11.0`
  - `src/object/object_representation.c:830, 890@10.2`, `src/base/object_representation.h:1418@10.2`, `src/base/system_parameter.c:2123@10.2`
  - 커밋 `ecaa13201` #2391, `ffb8a3819` #4066, `b6873b9b9` #2476, `288efc55b` #2483, `8e8ec6918` #3339, `991c8a4bc` #3283
- 클래스 객체: `src/base/object_representation.h:762@10.2, :762@11.0`, `src/object/transform_cl.c:3696, 4037@11.0`, `src/object/transform.c:201@11.0, :294@11.2`, `src/object/deduplicate_key.h:51@11.3`. 커밋 `14742376f` #3488, `0139ad69c` #3494, `7add5356d` #4401.
- 카탈로그: `src/storage/system_catalog.c:114@11.3, :116-117@11.4`, `src/transaction/boot_cl.c` (`boot_define_*`) @10.2..11.3 (serial :3230/3321@11.1, :3290@11.2; SP :3089-3189@11.3; att_name :3367@11.3; synonym :4080, server :4224@11.2), `src/object/schema_system_catalog_install.cpp:829-934@11.4`, `src/object/authenticate.c:131@10.2, :132@11.3`, `src/object/authenticate_grant.hpp:66-71@11.4`, `src/compat/dbtype_def.h:492@11.4`, `src/object/trigger_manager.c:7268@11.0, :7370@11.2`. 커밋 `f739bed2b` #2365, `540916ef6` #3541, `26ab1aab6` #3183, `1ea4a86e0` #5438, `45e44fb21` #5858, `b85c07b27` #5346, `e05227521` #4768, `2c2163932` (CBRD-26374).
- 스트림: `src/storage/storage_common.h:803, 905-945@11.0` (`OPERATOR_TYPE`, `FUNC_TYPE`), `src/query/xasl_to_stream.c` 함수 단위 비교 @10.2..11.4, `src/query/regu_var.hpp`, `src/xasl/xasl_predicate.hpp`, `src/query/string_opfunc.h`. 커밋 `4cc334318` #2460, `20c01592a` #1741, `3df36a110` #1647.
- B-tree: `src/storage/btree_load.h:216@11.2, :227@11.3, :202/210@11.4`. 커밋 `c1e7266a3` #4789.
- 로그: `src/transaction/log_storage.hpp:55@10.2, :70@11.0, :113-139@11.3, :118-124@11.4`, `src/query/crypt_opfunc.c:624-650@10.2, :672-676@11.0`, `src/transaction/log_page_buffer.c:4497@10.2, :4711@11.4`. 커밋 `6186f8cca` #7790.
- gdb `ptype /o`: `/home/cubrid/release/CUBRID-{10.2.18.9024,11.0.16.0419,11.2.9.0866,11.3.6.1321,11.4.6.1963}/lib/libcubrid.so`. 대상: `log_header`, `disk_volume_header`, `fileio_page_reserved`, `boot_dbparm`, `heap_hdr_stats`, `file_header`, `spage_header`.
- fastmig 현재 코덱: `~/dev/cubrid-fastmig@fec6138`. `crates/ondisk/src/{version_line,log_header,volume_header,boot_parm,log_page}.rs`, `crates/ondisk/src/value/string.rs`, `crates/ondisk/src/class_object/class_record.rs`, `crates/catalog/src/{system_classes,classify,same_slot_rows}.rs`.
- 앞선 조사: R1~R7 (`origin/research/fastmig-r{1..7}-*`), #474 리드 코멘트.
