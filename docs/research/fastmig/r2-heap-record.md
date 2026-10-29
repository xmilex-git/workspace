# R2 힙 페이지·OR 레코드·MVCC 헤더·vacuum 비트·값 인코딩: 11.4 → develop (#474)

기준: develop = `5b1867174` (`~/dev/cubrid-worktree/develop`), 11.4 = `origin/release/11.4` = `46212adcd`, 둘의 merge-base `13a115a0e`.
인용 형식: `dev:<path>:<line>` 은 develop 파일, `11.4:<path>:<line>` 은 `git show origin/release/11.4:<path>` 의 줄. "계산값" 은 구조체 정의에서 x86_64(LP64, GCC 비트필드 LSB 우선) 규칙으로 유도한 값으로, 엔진에 그 크기를 박은 static_assert 는 없다.

## 요약

1. **같은 것**: OR 레코드 MVCC 헤더(repid 워드·CHN·INSID·DELID·prev_version_lsa 오프셋과 플래그 비트), 슬롯 디렉터리(`SPAGE_SLOT`), `SPAGE_HEADER` 의 바이트 배치, `HEAP_CHAIN` 구조체(40B, 계산값), vacuum 상태 비트(`HEAP_CHAIN.flags` 상위 2비트) 값, vacuum 의 레코드 처리(`mvcc_satisfies_vacuum`, INSID/prev 제거, `spage_vacuum_slot`, `spage_compact`), 오버플로 페이지 구조, vacuum data 엔트리 구조. 함수 본문 비교에서 바뀐 곳은 오류 처리뿐이다.
2. **다른 것 (페이지)**: `HEAP_HDR_STATS` 가 통째로 바뀌었다(11.4 296B → develop 1152B, 둘 다 계산값; CBRD-26176 #7353 `e84a7f6dc`). develop 힙은 헤더 페이지 바로 뒤 체인에 **bestspace 전용 페이지**(1~4장, 페이지 크기에 따름)를 두고 `HEAP_CHAIN.flags` 하위 비트 `0x1`(BESTSPACE)·`0x2`(NOT_IN_HEAP)를 쓴다. `SPAGE_HEADER` 비트필드 bit1(`need_update_best_hint`)은 develop 에서 reserved 다. 따라서 **모든 힙 파일의 헤더 페이지는 재작성 + 새 페이지 할당**이 필요하다(배치 보존과 충돌하지 않는 "추가 할당").
3. **다른 것 (값)**: CHAR 는 고정 영역 → 가변 영역(VARCHAR 와 같은 문자열 인코딩 + LZ4, #7326 `a9fca9002`), NUMERIC 은 16B 2의 보수 고정 → 3B 헤더 + 절댓값 가변(4/8/12/16/20B, #6486 `de7bc5ec2`), NCHAR/VARNCHAR 타입 자체가 제거(#6420 `bb8f3cbda`). 나머지 타입(INT·BIGINT·SHORT·FLOAT·DOUBLE·MONETARY·날짜/시간 9종·OBJECT·OID·ENUM·BIT·VARBIT·VARCHAR·JSON·BLOB/CLOB·SET 계열 자체)의 디스크 바이트는 같다.
4. **판정**: representation(컬렉션 원소 도메인 포함)에 CHAR·NCHAR·NUMERIC 이 하나라도 있으면 그 representation 의 레코드는 **transform**(디코드 → develop 레이아웃 재인코딩, 고정/가변 재배치·bound bit·오프셋 표 재계산). 없으면 **copy + patch**(바이트 그대로, VARNCHAR 는 카탈로그 도메인만 VARCHAR 로).
5. **vacuum 잔여 페이지 선택**: 출발 DB 의 `oldest_unvacuumed`(OU)를 로그 헤더·vacuum data 첫 엔트리로 엔진과 같은 식으로 구하고, 헤더 페이지는 항상, 일반 페이지는 `status==ONCE` 또는 `status==UNKNOWN && max_mvccid >= OU` 일 때 레코드 단위 처리 대상이다. vacuum data 가 비고 `does_block_need_vacuum==false` 면 OU = `mvcc_next_id` 라 일반 페이지는 하나도 대상이 아니다(체인 리셋만).
6. **레코드 정리 불변식**: DELID 유효 레코드는 슬롯 삭제(슬롯 id 보존, reuse-OID 힙은 `REC_DELETED_WILL_REUSE`, 아니면 `REC_MARKDELETED`), 그 밖에는 INSID·PREV 를 헤더에서 빼고 본문을 당긴다. BIGONE 의 오버플로 헤더는 32B 를 유지하며 값만 바꾼다(INSID=3, DELID=0, prev_lsa=NULL). 슬롯 디렉터리는 절대 줄이지 않는다(`spage_compact` 는 레코드만 압축).
7. **prev_version_lsa 는 무조건 제거**해야 한다: 출발 로그를 버리므로 그 LSA 는 도착 DB 에서 매달린 포인터다.
8. 페이지마다 `max_mvccid=0`, vacuum 상태 NONE, 하위 플래그 0 으로 리셋하면 엔진의 새 페이지 초기 상태(`heap_vpid_init_new`)와 같다.
9. develop 의 최대 슬롯 레코드 길이는 11.4 보다 커서(16K 페이지 기준 16052 → 16276, 계산값) 기존 HOME 레코드가 develop 기준으로 "big" 이 되는 일은 없다.
10. CBRD-27819 S2(10000진 NUMERIC)는 보류 상태다. 머지되면 NUMERIC 재인코딩 목표 형식이 바뀌고 디스크 호환 번호도 올라간다(#471 D3·D7). 지금 있는 S0/S1 은 디스크 형식을 바꾸지 않는다.

## 1. 페이지·레코드 레이아웃

모든 오프셋은 페이지 버퍼의 사용자 영역 시작(`PAGE_PTR`, FILEIO 예약 헤더 뒤) 기준이다. FILEIO 페이지 헤더(LSA·ptype·TDE 비트)는 R1 범위다.

### 1.1 SPAGE_HEADER (네이티브 엔디언 메모리 이미지, 32B 계산값)

| off | size | 필드 | 11.4 | develop | 변경 |
|---|---|---|---|---|---|
| 0 | 2 | `num_slots` (INT16) | 같음 | 같음 | – |
| 2 | 2 | `num_records` | 같음 | 같음 | – |
| 4 | 2 | `anchor_type` (힙은 `ANCHORED_DONT_REUSE_SLOTS`=2) | 같음 | 같음 | – |
| 6 | 2 | `alignment` (힙은 `HEAP_MAX_ALIGN`=4) | 같음 | 같음 | – |
| 8 | 4 | `total_free` | 같음 | 같음 | – |
| 12 | 4 | `cont_free` | 같음 | 같음 | – |
| 16 | 4 | `offset_to_free_area` | 같음 | 같음 | – |
| 20 | 4 | `reserved1` | 같음 | 같음 | – |
| 24 | 4 | `flags` (항상 0) | 같음 | 같음 | – |
| 28 | 4 | 비트필드 워드: bit0 `is_saving` | bit1 `need_update_best_hint`, bit2-31 reserved | bit1-31 reserved | `e84a7f6dc` #7353 |

근거: `11.4:src/storage/slotted_page.h:64-84`, `dev:src/storage/slotted_page.h:64-82`, 힙 페이지 초기화 `dev:src/storage/slotted_page.c:1065-1089`(reserved 0 기록), 힙 anchor `dev:src/storage/heap_file.c:1081-1084`, `HEAP_MAX_ALIGN` `dev:src/storage/heap_file.h:64`. develop 은 reserved 비트를 읽지 않는다(`rg reserved_bits` 는 초기화 한 곳뿐, `dev:src/storage/slotted_page.c:1080`).

### 1.2 SPAGE_SLOT (네이티브 u32, 페이지 끝에서 거꾸로)

슬롯 i 의 위치 = `PAGESIZE - 4*(i+1)` (`dev:src/storage/slotted_page.c:4586-4587`). 비트: `offset_to_record` 0-13, `record_length` 14-27, `record_type` 28-31 (`dev:src/storage/slotted_page.h:86-91`, 11.4 동일 `11.4:src/storage/slotted_page.h:88-93`). 빈 슬롯은 offset 0(`SPAGE_EMPTY_OFFSET`, `dev:src/storage/slotted_page.c:85-88`). 레코드 타입 값 `REC_HOME`=2, `REC_NEWHOME`=3, `REC_RELOCATION`=4, `REC_BIGONE`=5, `REC_MARKDELETED`=6, `REC_DELETED_WILL_REUSE`=7, `REC_ASSIGN_ADDRESS`=1 (`dev:src/storage/storage_common.h:1172-1212`). 변경 없음.

### 1.3 HEAP_CHAIN (일반 힙 페이지의 슬롯 0, 네이티브, 40B 계산값)

| off | size | 필드 | 11.4 | develop | 변경 |
|---|---|---|---|---|---|
| 0 | 8 | `class_oid` (pageid i32, slotid i16, volid i16) | 같음 | 같음 | – |
| 8 | 8 | `prev_vpid` (pageid i32, volid i16, pad 2) | 같음 | 같음 | – |
| 16 | 8 | `next_vpid` | 같음 | 같음 | – |
| 24 | 8 | `max_mvccid` (u64) | 같음 | 같음 | – |
| 32 | 4 | `flags`: `0xC0000000` vacuum 상태 | 상위 2비트만 | + `0x1` BESTSPACE, `0x2` NOT_IN_HEAP | `e84a7f6dc` #7353 |
| 36 | 4 | pad (u64 정렬) | – | – | – |

vacuum 상태 해석(두 버전 동일): `flags & 0xC0000000` 가 0 → NONE, `0x80000000` → ONCE, 그 밖(`0x40000000`, `0xC0000000`) → UNKNOWN (`11.4:src/storage/heap_file.c:241-268`, `dev:src/storage/heap_file.c:228-272`). 11.4 는 하위 비트를 늘 0 으로 썼다(`11.4:src/storage/heap_file.c:4313,5660,16664,16710,25875`). 헤더 페이지와 일반 페이지는 슬롯 0 레코드 길이로만 구분한다: `length == sizeof(HEAP_CHAIN)` 이면 일반, 아니면 헤더(`dev:src/storage/heap_file.c:25031-25036,2826-2830`).

### 1.4 HEAP_HDR_STATS (헤더 페이지의 슬롯 0, 네이티브)

11.4 (`11.4:src/storage/heap_file.c:183-232`, 합계 296B 계산값):

| off | size | 필드 |
|---|---|---|
| 0 | 8 | `class_oid` |
| 8 | 8 | `ovf_vfid` (fileid i32, volid i16, pad) |
| 16 | 8 | `next_vpid` |
| 24 | 4 | `unfill_space` |
| 28 | 40 | `estimates.{num_pages, num_recs, recs_sumlen(float), num_other_high_best, num_high_best, num_substitutions, num_second_best, head_second_best, tail_second_best, head}` |
| 68 | 8 | `estimates.last_vpid` |
| 76 | 8 | `estimates.full_search_vpid` |
| 84 | 80 | `estimates.second_best[10]` (VPID) |
| 164 | 120 | `estimates.best[10]` (`HEAP_BESTSPACE` = VPID + int, `11.4:src/storage/heap_file.h:120-124`) |
| 284 | 12 | `reserve0..2_for_future` |

develop (`dev:src/storage/heap_file.c:190-224`, 합계 1152B 계산값):

| off | size | 필드 |
|---|---|---|
| 0 | 8 | `class_oid` |
| 8 | 8 | `ovf_vfid` |
| 16 | 8 | `next_vpid` (= 첫 bestspace 페이지) |
| 24 | 8 | `last_vpid` |
| 32 | 4 | `unfill_space` (CHAIN.flags 와 같은 오프셋 — `dev:src/storage/heap_file.c:2853-2855` 주석이 확인) |
| 36 | 4 | `num_pages` (사용자 페이지 추정치, bestspace 페이지 제외) |
| 40 | 8 | `num_recs` (u64) |
| 48 | 8 | `recs_sumlen` (u64) |
| 56 | 8 | `bestspace.num_candidates` (size_t) |
| 64 | 1024 | `bestspace.candidates[128]` (`bestspace_entry` 8B: u16 freespace, i16 volid, i32 pageid — `dev:src/storage/bestspace.hpp:47-64`) |
| 1088 | 8 | `bestspace.num_shards` |
| 1096 | 8 | `bestspace.num_pages` |
| 1104 | 32 | `bestspace.pages[4]` (VPID) |
| 1136 | 12 | `reserve0..2` |
| 1148 | 4 | pad (u64 정렬) |

변경 커밋: `e84a7f6dc` CBRD-26176 #7353 (lock-free bestspace 재설계, PR 본문: "bestspace 정보는 별도의 shard page에 위치"). 같은 커밋이 `heap_Maxslotted_reclength` 식도 바꿨다(1.9).

### 1.5 develop bestspace 페이지 (11.4 에 없음)

`heap_create_bestspace` (`dev:src/storage/heap_file.c:3896-4073`):
- 페이지 수 = `ceil(max_shards * 64 / entries_per_page)`, `max_shards` = `PRM_ID_BESTSPACE_SHARD_COUNT` 범위 최댓값 28(기본 8, `dev:src/base/system_parameter.c:5497-5505`), `entries_per_page = (spage_max_record_size() - 40 - 4) / 8`, `spage_max_record_size() = PAGESIZE - 32 - 4` (`dev:src/storage/slotted_page.c:841-844`). 계산값: 16K → 1장, 8K → 2장, 4K → 4장(상한 `MAX_SHARD_PAGE_COUNT`=4, `dev:src/storage/bestspace.hpp:75-76`).
- 각 페이지: 슬롯 0 = `HEAP_CHAIN`{class_oid, max_mvccid=0, flags = BESTSPACE(0x1), 상태 NONE}, 슬롯 1(`HEAP_BESTSPACE_ENTRIES_SLOTID`, `dev:src/storage/heap_file.c:247`) = `bestspace_entry` 배열(남은 엔트리 수 × 8B), 모두 null(`freespace=0, volid=-1, pageid=-1`), 첫 페이지의 첫 엔트리만 헤더 페이지.
- 체인: 헤더 → pages[0] → … → pages[n-1] → (기존 첫 데이터 페이지). `heap_hdr.next_vpid = pages[0]` (`dev:src/storage/heap_file.c:4001-4002`). 스캔은 `HEAP_PAGE_IS_BESTSPACE` 페이지를 건너뛴다(`heap_page_next`, `dev:src/storage/heap_file.c:2816-2832`; 병렬 스캔·btree_load·histogram 도 같은 검사).
- 헤더 초기값: `num_shards` = 시스템 파라미터 값(root 클래스 힙은 1, `dev:src/storage/heap_file.c:5856-5863`), `num_candidates=0`·candidates null(`dev:src/storage/heap_file.c:3799-3814`), `unfill_space = DB_PAGESIZE * hf_unfill_factor` (`dev:src/storage/heap_file.c:4915`).

### 1.6 OR 레코드 MVCC 헤더 (빅엔디언, prev_lsa 만 네이티브) — 변경 없음

repid 워드(off 0, BE i32) 비트: 31 = `OR_BOUND_BIT_FLAG`(고정 속성이 있을 때 1), 29-30 = 가변 오프셋 크기(`01`→1B, `10`→2B, `11`→4B), 24-28 = MVCC 플래그(`0x01` INSID, `0x02` DELID, `0x04` PREV_VERSION), 0-23 = repid.

| off | size | 필드 | 존재 조건 | 11.4 = develop |
|---|---|---|---|---|
| 0 | 4 | repid + 플래그 | 항상 | 같음 |
| 4 | 4 | CHN (BE i32) | 항상 (MVCC 클래스는 삽입 시 0) | 같음 |
| 8 | 8 | INSID (BE u64) | flag & 0x01 | 같음 |
| 8 or 16 | 8 | DELID (BE u64) | flag & 0x02 | 같음 |
| 다음 | 8 | prev_version_lsa (네이티브 `log_lsa` 비트필드 pageid:48, offset:16; NULL = 전 비트 1) | flag & 0x04 | 같음 |

헤더 길이 = `mvcc_header_size_lookup[flag & 7]` = 8 + 8·popcount(flag&7) (`dev:src/object/object_representation.c:71-80`). 근거: `dev:src/base/object_representation_constants.h:140-173` (11.4 와 diff 0), `dev:src/base/object_representation.h:530-616` (`11.4:src/base/object_representation.h:474-555` 와 오프셋 매크로 동일; diff 는 OR_BUF 오류 처리·overflow 매크로뿐), BE 쓰기 `dev:src/base/object_representation.h:161-170`, prev_lsa memcpy `dev:src/base/object_representation_sr.c:4707-4721`, NULL LSA `dev:src/transaction/log_lsa.hpp:113-114,158-163`, `MVCCID_NULL`=0·`MVCCID_ALL_VISIBLE`=3·`MVCCID_FIRST`=4 `dev:src/storage/storage_common.h:339-345`. MVCC 비활성 클래스(root, db_serial, _db_collation, db_ha_apply_info)는 8B 헤더(repid 워드 + CHN)만 쓴다(`dev:src/transaction/mvcc.c:683-709`).

### 1.7 레코드 본문 배치 — 규칙 동일, 소속 속성만 바뀜

`[MVCC 헤더][가변 오프셋 표: (n_var+1)×offset_size, 4B 정렬][고정 영역 fixed_length (4B 정렬)][bound bits: OR_BOUND_BIT_BYTES(n_fixed)][가변 값들]`
- 오프셋 표 값은 헤더 끝(표 시작) 기준이라 헤더가 줄거나 늘어도 값이 바뀌지 않는다(`dev:src/storage/heap_file.c:12597,12752`; 읽기 `OR_VAR_OFFSET` 이 현재 `OR_HEADER_SIZE` 를 더함 `dev:src/base/object_representation.h:625-628`).
- 마지막 엔트리(n_var)는 가변 영역 끝. 길이 0 인 엔트리 = NULL.
- offset_size: 헤더(16) + 표 + bound bits + payload 가 127(`OR_MAX_BYTE`) 초과면 2B, 32767 초과면 4B (`dev:src/storage/heap_file.c:12269-12294`, 11.4 `heap_attrinfo_get_disksize` 같은 규칙 `11.4:src/storage/heap_file.c:11528-11575`).
- 고정 속성 위치 = repr 속성 순서대로 `tp_domain_disk_size` 누적, 가변 속성 index = `i - n_fixed` (`dev:src/base/object_representation_sr.c:2524-2535,3018-3028`).
- 속성 순서(스키마 저장 순서): 고정 속성은 정렬 요구 내림차순, 같은 정렬이면 디스크 크기 오름차순(`order_atts_by_alignment`, `dev:src/object/schema_manager.c:9962-9991`), 그 뒤 가변 속성은 기존 클래스 속성 순서대로(`build_storage_order`, `dev:src/object/schema_manager.c:10022-10111`). 두 함수는 11.4 와 같다(차이는 DEDUPLICATE assert 한 줄).

### 1.8 REC_RELOCATION / REC_NEWHOME / REC_BIGONE / 오버플로 — 변경 없음

- `REC_RELOCATION` 홈 슬롯 본문 = 네이티브 `OID`(8B) → 같은 힙의 `REC_NEWHOME` 슬롯. MVCC 헤더는 NEWHOME 쪽에 있다(`dev:src/storage/heap_file.c:5695,5733`).
- `REC_BIGONE` 홈 슬롯 본문 = 첫 오버플로 페이지 OID. 첫 오버플로 페이지 = `OVERFLOW_FIRST_PART{VPID next_vpid; int length; data[]}` (data 는 off 12), 나머지 = `OVERFLOW_REST_PART{VPID next_vpid; data[]}` (`dev:src/storage/overflow_file.h:37-50`, 11.4 와 diff 0). 오버플로 레코드의 MVCC 헤더는 항상 32B(플래그 7) — `heap_set_mvcc_rec_header_on_overflow` 가 INSID·DELID 플래그를 강제하고 크기 32 를 assert (`dev:src/storage/heap_file.c:19750-19780`).

### 1.9 레코드 크기 상한

| | 식 | 16K 계산값 | 근거 |
|---|---|---|---|
| 11.4 | `spage_max_record_size() - sizeof(HEAP_HDR_STATS)` | 16348 − 296 = 16052 | `11.4:src/storage/heap_file.c:5122-5124` |
| develop | `ALIGN_BELOW(spage_max_record_size() - 40 - 8*4, 4)` | 16348 − 72 = 16276 | `dev:src/storage/heap_file.c:3742-3744`, `e84a7f6dc` |

길이 > 상한 이면 BIGONE (`heap_is_big_length`, `dev:src/storage/heap_file.c:1058-1061`).

## 2. 타입별 값 인코딩 차이표

`PR_TYPE` 헤더 필드(variable_p, size, disksize, alignment) 비교(`11.4:src/object/object_primitive.c` vs `dev:src/object/object_primitive.c:913-1720`)와 `mr_data_{writeval,readval,lengthval,writemem,readmem,lengthmem}` 및 `or_*` 본문 비교 결과.

| 타입 | 11.4 디스크 | develop 디스크 | 변경 커밋 | 판정 |
|---|---|---|---|---|
| CHAR(n) | 고정 영역, `STR_SIZE(n,cs)` = n×mult 바이트(UTF-8 4, EUC-KR 3, 그 외 1), 공백 채움, 정렬 1 (`11.4:...object_primitive.c:12302`, writer `11859-11935`) | 가변 영역, VARCHAR 와 같은 문자열 인코딩(아래), n 글자까지 공백 채움 후 압축 (`dev:...object_primitive.c:12694`, `12024-12230`) | `a9fca9002` CBRD-26956 #7326 (#7164 `83b29b02c` 의 CHAR 가변화만 유지) | **재인코딩** |
| NUMERIC(p,s) | 고정 16B(`DB_NUMERIC_BUF_SIZE = 2*sizeof(double)`, `11.4:src/compat/dbtype_def.h:595`; `OR_NUMERIC_SIZE` `11.4:...object_primitive.c:119`), 비스케일 정수의 BE 2의 보수, p·s 는 도메인에만 | 가변 영역, 3B 헤더 + 절댓값 BE 하위 바이트, 총 4/8/12/16/20B (`dev:...object_primitive.c:117-157,8722-8775`), NULL 은 길이 0 | `de7bc5ec2` CBRD-26006 #6486, NULL 처리 `5ab88c6b1` CBRD-26887 #7263 | **재인코딩** |
| NCHAR(n) | CHAR 와 같은 고정 인코딩(`tp_NChar` `11.4:...:13216`) | 타입 없음(`DB_TYPE_NCHAR_DEPRECATED`, `dev:src/compat/dbtype_def.h:779`) | `bb8f3cbda` CBRD-24156 #6420 | **CHAR 로 타입 변경 + 재인코딩** |
| VARNCHAR | VARCHAR 와 같은 바이트(`11.4:...:13701-13790`) | 타입 없음 | `bb8f3cbda` #6420 | 카탈로그 도메인만 VARCHAR 로, 바이트 copy |
| VARCHAR | 1B 길이/0xFF+압축 헤더, LZ4 | 같음(writer 차이는 assert 한 줄, 압축 호출 래퍼만 `f1919e0d1` #6513) | – | copy |
| SET/MULTISET/SEQUENCE | 원소 도메인이 고정폭이면 bound bit 배열, 아니면 오프셋 표(`or_packed_set_info`) | 같은 규칙, 단 CHAR/NUMERIC 원소는 이제 가변 → 오프셋 표 | 원소 타입 변경에 종속 | 원소 도메인에 CHAR/NCHAR/NUMERIC 이 있으면 **재인코딩**, 없으면 copy |
| DATETIME | 8B | 같음; 읽기에서 date=time=UINT_MAX 를 NULL 로 해석(`dev:...:3984-4000`, `1f1263217` #6443) | – | copy (그 패턴은 11.4 정상 값이 아님) |
| 도메인 직렬화(컬렉션·카탈로그) | scale <255 이면 carrier 에 직접 | scale 0~127 직접, 그 밖은 확장(`dev:src/object/object_representation.c:2529-2541`) | `de7bc5ec2` | 11.4 scale ≤38 이라 바이트 같음 |
| INT·SHORT·BIGINT·FLOAT·DOUBLE·MONETARY·DATE·TIME·TIMESTAMP(TZ/LTZ)·DATETIME(TZ/LTZ)·OBJECT·OID·ENUM(2B)·BIT·VARBIT·JSON·BLOB/CLOB | – | 함수 본문 차이는 `or_abort`/`or_overflow` → assert·반환 코드뿐 | – | copy |

### 2.1 develop 문자열 인코딩 (CHAR 재인코딩 목표)

값 바이트열 s, 길이 L(바이트).
- `L < 255`: `[L:u8][s][0x00]` 후 4B 경계까지 0 패딩 (`pr_write_uncompressed_string_to_buffer`, `dev:...object_primitive.c:14742-14776`).
- `L >= 255`: `[0xFF][clen:BE i32][L:BE i32][데이터][0x00]` + 4B 패딩. LZ4 결과 길이가 `L-8` 미만이면 clen = 압축 길이, 데이터 = 압축본; 아니면 clen = 0, 데이터 = 원본 (`dev:...:14665-14728, 14790-14837, 14896-14972`; 임계 `OR_MINIMUM_STRING_LENGTH_FOR_COMPRESSION`=255 `dev:src/base/object_representation.h:1450-1453`). 읽기는 clen>0 이면 LZ4 블록을 풀고 0 이면 원본으로 읽으므로, 압축 여부는 정확성에 영향이 없다.
- 정렬 패딩은 버퍼 절대 주소 기준(`or_put_align32`, `dev:src/base/object_representation.h:1571-1584`)이고, 레코드 시작이 4B 정렬이므로 레코드 내부 오프셋 기준과 같다.

### 2.2 NUMERIC 변환 (11.4 16B → develop)

11.4 값 N = 16B BE 2의 보수(음수 판정 `N[0]&0x80`, `11.4:src/query/numeric_opfunc.c:166-169`; 부정은 2의 보수 `:597-612`). develop 은 17B BE 절댓값 + 따로 둔 부호(`dev:src/compat/dbtype_def.h:647`, `dev:src/compat/dbtype_function.i:1632-1699`).
- `neg = N[0] & 0x80`; `mag = neg ? (−N) : N` (16B).
- `nbytes` = mag 의 선행 0 바이트를 뺀 길이, mag==0 이면 1 (`mr_get_fixed_numeric_size`, `dev:...object_primitive.c:8945-8989`).
- `size = {1:4, 2-5:8, 6-9:12, 10-13:16, 14-16:20}[nbytes]` (`_gv_mr_fixed_numeric_bytes_to_size`, `dev:...:155-157`).
- 바이트 = `[size | (neg ? 0x80 : 0)][p][s]` + `(0x00 ∥ mag)` 17B 의 하위 `size−3` 바이트 (`dev:...:8722-8775`). p·s 는 컬럼 도메인 값(11.4 는 0 ≤ s ≤ p ≤ 38 이라 scale 부호 비트 0). 0 은 neg=0.
- 읽기는 헤더의 p·s 를 쓰고 도메인 p 가 40 일 때만 floating 으로 본다(`dev:...:8777-8845`) — 11.4 도메인은 p ≤ 38 이라 항상 고정 NUMERIC.

### 2.3 CHAR 디코드 (11.4 고정 필드)

`mem_length = STR_SIZE(n, codeset)`; 값 바이트 = 필드 앞에서 codeset 기준 n 글자의 바이트(`intl_char_size`), 결과가 0 이면 mem_length 전체 (`11.4:src/object/object_primitive.c:12044-12072`). 11.4 writer 가 공백으로 채웠으므로(`11.4:src/object/object_primitive.c:11896-11904`) 이 n 글자가 develop writer 가 패딩 후 쓰는 문자열과 같다(`dev:src/object/object_primitive.c:12158-12172`). NULL 은 bound bit 0 → develop 에서 가변 엔트리 길이 0.

## 3. Rust 가 구현할 규칙 (기계적 검사)

### R1 페이지 분류
1. ptype 이 HEAP 인 페이지에서 슬롯 0 길이 L0 을 읽는다. L0 == 40 → 일반 페이지(`HEAP_CHAIN`), 출발(11.4)에서 L0 == 296 → 헤더 페이지. 그 밖 = 손상 → 중단.
2. 일반 페이지에서 `flags & ~0xC0000000 != 0` 이면 11.4 출발로는 불가능한 값 → 중단.

### R2 vacuum 잔여 페이지 선택 (출발 DB 기준)
1. OU 계산(엔진 `vacuum_data::set_oldest_unvacuumed_on_boot`, `dev:src/query/vacuum.c:8104-8122` 와 같은 식; 11.4 동일 구조):
   - `log_hdr.does_block_need_vacuum == false` 이면 `oldest_visible = log_hdr.mvcc_next_id`, 아니면 `log_hdr.oldest_visible_mvccid` (필드 `11.4:src/transaction/log_storage.hpp:131,167,173`).
   - vacuum data 가 비어 있으면(첫 페이지 `index_unvacuumed`..`index_free` 범위에 미처리 엔트리 없음, 구조 `dev:src/query/vacuum.c:106-123,196-214`, 11.4 동일) OU = oldest_visible, 아니면 OU = 첫 엔트리 `oldest_visible_mvccid`.
2. 대상 = (헤더 페이지) ∪ (일반 페이지 중 status == ONCE) ∪ (일반 페이지 중 status == UNKNOWN && `max_mvccid >= OU`). NONE 페이지와 `max_mvccid < OU` 인 UNKNOWN 페이지는 엔진도 "다 vacuum 됨" 으로 본다(`vacuum_is_mvccid_vacuumed`, `dev:src/query/vacuum.c:7478-7486`; 사용처 `dev:src/storage/heap_file.c:25062`).
3. 헤더 페이지는 체인이 없어 MVCC 연산 추적 대상이 아니다(`dev:src/storage/heap_file.c:25031-25036`) → 레코드가 있으면 항상 레코드 단위 검사.
4. 비용 = 대상 페이지 수 × 페이지당 레코드 처리. vacuum data 가 비고 does_block_need_vacuum 이 거짓이면 일반 페이지 대상 0.

### R3 레코드 단위 정리 (대상 페이지의 홈 슬롯만; vacuum 과 같이 `REC_NEWHOME` 은 홈에서 따라간다, `dev:src/query/vacuum.c:1738-1742`)
F = 헤더 플래그. "삭제 확정" = `F & DELID && DELID != 0` (`MVCC_IS_HEADER_DELID_VALID`, `dev:src/transaction/mvcc.h:87-89`). 출발 DB 는 활성 트랜잭션이 없으므로 모든 DELID 는 커밋된 삭제다(abort 는 undo 로 DELID 를 되돌림).
- `REC_HOME`:
  - 삭제 확정 → 슬롯 삭제: `offset=0`, `type = reuse? 7 : 6`, `record_length` 는 그대로, `num_records -= 1`, `total_free += len + DB_WASTED_ALIGN(len, 4)` (`spage_vacuum_slot`, `dev:src/storage/slotted_page.c:4826-4864`). reuse = 힙 파일 타입이 `FILE_HEAP_REUSE_SLOTS` (`dev:src/storage/heap_file.c:1092-1107`).
  - 그 밖에 `F & (INSID|PREV)` → 헤더에서 INSID(8B)·PREV(8B) 제거, DELID 가 있으면(값 0) 남긴다, 플래그 비트 클리어, 본문을 당겨 `length -= 8·(제거 개수)` (`vacuum_heap_record_insid_and_prev_version`, `dev:src/query/vacuum.c:2294-2335`). 엔진은 INSID 가 3(ALL_VISIBLE)이 아닐 때만 하지만(`dev:src/transaction/mvcc.c:321-374`), 도구는 PREV 플래그만 남은 경우도 지워야 한다 — 그 LSA 는 버린 로그를 가리킨다.
- `REC_RELOCATION`: 대상 NEWHOME 의 헤더로 판정. 삭제 확정 → 홈 슬롯을 위 규칙(reuse 여부 적용)으로, NEWHOME 슬롯은 **항상 `REC_DELETED_WILL_REUSE`** 로 삭제(`dev:src/query/vacuum.c:2387,2403-2431`). 아니면 NEWHOME 에서 INSID·PREV 제거(`:2211-2265`).
- `REC_BIGONE`: 첫 오버플로 페이지 data(off 12)의 32B 헤더로 판정. 삭제 확정 → 홈 슬롯 삭제 + 오버플로 체인 전 페이지 해제(파일 관리자, `heap_ovf_delete` `dev:src/storage/heap_file.c:6226`). 아니면 **크기 유지**: 플래그 7 유지, INSID = 3(BE), DELID = 0, prev_lsa = 0xFF×8 (`dev:src/query/vacuum.c:2266-2293`, `dev:src/storage/heap_file.c:19763-19779`).
- `REC_NEWHOME`(홈 없이 단독 방문), `REC_ASSIGN_ADDRESS`, 6, 7 → 손대지 않는다. MVCC 비활성 클래스 레코드(8B 헤더)도 손대지 않는다.
- 슬롯 디렉터리는 줄이지 않는다: `spage_reclaim` 류(꼬리 슬롯 제거, MARKDELETED→WILL_REUSE)는 compactdb 경로(`dev:src/storage/heap_file.c:5919`)이고 vacuum 은 하지 않는다. OID 보존의 전제다.

### R4 페이지 재구성 불변식 (`spage_compact` 와 같은 결과, `dev:src/storage/slotted_page.c:1144-1240`)
1. 살아 있는 슬롯(offset ≠ 0)을 원래 offset 오름차순으로, `to = 32` 부터 `DB_ALIGN(to, 4)` 위치에 차례로 놓고 slot.offset 갱신.
2. `offset_to_free_area = DB_ALIGN(to_end, 4)`, `total_free = cont_free = PAGESIZE − offset_to_free_area − 4·num_slots`, `num_records` = 살아 있는 슬롯 수.
3. 검증(`spage_check`, `dev:src/storage/slotted_page.c:4369-4420`): `32 + 4·num_slots + Σ DB_ALIGN(len_i, 4) + total_free ≤ PAGESIZE`, `cont_free + offset_to_free_area + 4·num_slots ≤ PAGESIZE`, `0 ≤ cont_free ≤ total_free`, `num_records ≤ num_slots`, 레코드 타입 ≤ 7.
4. 비트필드 워드는 bit0(`is_saving`, 힙은 1)만 남기고 0 — 11.4 의 bit1 을 지운다.

### R5 체인 리셋 (모든 일반 페이지)
`max_mvccid = 0`, `flags = 0`(상태 NONE, BESTSPACE·NOT_IN_HEAP 0). 엔진 새 페이지 초기 상태와 같다(`dev:src/storage/heap_file.c:2892-2929`, `:3967-3971`). 이렇게 하면 도착 `mvcc_next_id` 가 무엇이든 `heap_page_update_chain_after_mvcc_op` 의 `MVCC_ID_PRECEDES(chain->max_mvccid, mvccid)` assert(`dev:src/storage/heap_file.c:25045`)를 만족한다. 도착 로그 헤더의 `mvcc_next_id` 는 출발 값 이상으로 두는 것이 안전하다(INSID 가 남지 않으면 필수는 아님 — R1/로그 티켓).

### R6 헤더 페이지 재작성 + bestspace 페이지 (모든 힙 파일)
1. 슬롯 0 을 develop `HEAP_HDR_STATS`(1152B 계산값, 1.4 표)로 교체: class_oid·ovf_vfid·next_vpid(아래)·last_vpid(마지막 데이터 페이지)·unfill_space(11.4 값 유지)·num_pages(데이터 페이지 수)·num_recs·recs_sumlen(실측 또는 0)·candidates null·`num_candidates=0`·`num_shards`(일반 힙 8, root 1)·bestspace.num_pages·pages[].
2. 헤더 페이지가 856B(계산값) 더 필요하다. 모자라면 헤더 페이지의 HOME 레코드 일부를 다른 페이지로 옮기고 홈 슬롯을 `REC_RELOCATION`(OID 8B)으로 바꾼다 — OID 는 그대로다.
3. bestspace 페이지 n 장을 같은 힙 파일에 새로 할당(파일 관리자 티켓)하고 1.5 형식으로 초기화, 체인을 헤더 → bs[0..n-1] → 기존 첫 데이터 페이지로 다시 잇는다(기존 첫 데이터 페이지의 `prev_vpid` = bs[n-1]).
4. 엔트리 값은 힌트다(PR #7353 본문: "정확하지 않거나 소실되는 것을 전제") — null 로 두어도 정확성은 유지된다.

### R7 transform 판정과 재인코딩
1. 판정: representation 의 속성 도메인(재귀적으로 컬렉션 원소 도메인 포함)에 `DB_TYPE_CHAR`(4), `DB_TYPE_NCHAR`(26), `DB_TYPE_NUMERIC`(22)이 있으면 transform, 아니면 copy+patch.
2. transform: 11.4 representation(레코드의 repid)으로 디코드 → 카탈로그가 정한 develop representation 으로 다시 쓴다. 새 representation 의 고정/가변 분할은 develop `variable_p` 기준(CHAR·NUMERIC 가변), 순서는 1.7 규칙. 고정 속성이 0 개가 되면 bound bit 플래그 0, bound bit 바이트 없음(`dev:src/storage/heap_file.c:12380-12386`).
3. 헤더는 정리 후 형태로 쓴다: MVCC 클래스는 8B(플래그 0, CHN 은 출발 값 유지), 비 MVCC 는 8B. offset_size 는 1.7 규칙으로 다시 고른다.
4. 새 길이가 홈 페이지에 들어가면 같은 슬롯에 둔다. 안 들어가면 NEWHOME 을 같은 힙의 여유 페이지에 두고 홈을 `REC_RELOCATION` 으로. 길이 > develop 상한(1.9)이면 BIGONE(오버플로 파일이 없으면 생성 — 파일 티켓, 헤더 `ovf_vfid` 갱신, 첫 오버플로 헤더 32B·플래그 7). 원래 BIGONE 이면 오버플로 체인을 새 길이로 다시 쓴다(페이지 수 변동 시 할당/해제).
5. 컬렉션 값: `or_packed_set_info` 규칙(`dev:src/object/object_representation.c:3880-3949`)으로 원소 도메인이 단일·고정폭이면 bound bit, 아니면 오프셋 표; CHAR/NUMERIC 원소는 develop 에서 가변이므로 오프셋 표 형태로 다시 쓴다(원소 값은 2.1·2.2).

### R8 copy+patch 대상 레코드의 검사
레코드 헤더 repid 가 카탈로그에 있는 develop representation 이어야 하고, 그 representation 의 n_fixed·fixed_length·n_var 가 11.4 와 같아야 한다(copy 의 전제). R3 정리만 적용.

## Open questions

1. representation 정책: 옛 repid 레코드를 최신 repid 로 올려 쓸지, 옛 representation 들을 develop 형식(CHAR/NUMERIC 가변)으로 다시 만들어 카탈로그에 둘지 — 카탈로그 티켓의 결정이 필요하다. develop 은 옛 repid 레코드를 카탈로그의 그 representation 으로 읽으며 앞 `n_fixed` 개를 고정으로 본다(`dev:src/base/object_representation_sr.c:3018-3028`). 그래서 옛 representation 을 11.4 형태로 남기면 CHAR/NUMERIC 위치를 `tp_domain_disk_size`(develop 에서 −1)로 계산해 깨진다.
2. 헤더 페이지에 856B 가 없을 때 옮길 레코드를 고르는 순서(작은 것부터인지, 마지막 슬롯부터인지)와, 그 결과가 검증기·unloaddb 집합 비교에 영향이 없는지.
3. NCHAR 컬럼이 있는 11.4 DB 를 받을지 거부할지. 받는다면 CHAR 로 바꾸는데, 그때 codeset·collation 매핑은 카탈로그 티켓이 정한다.
4. CHAR 재인코딩에서 LZ4 압축을 할지. 정확성에는 영향이 없다(2.1). 대신 공간과 "엔진이 쓴 것과 같은 바이트" 기준이 갈린다. 압축하려면 cubcompress 의 LZ4 설정(가속 계수)을 따로 확인해야 한다.
5. 집합(SET) 원소 재인코딩의 세부(태그 값, 도메인 포함 여부별 바이트)는 `or_put_set`·`or_put_value` 를 따라 별도로 표로 만들어야 한다 [VERIFY].
6. `num_recs`·`recs_sumlen`·bestspace 엔트리를 실측해 채울지(옵티마이저 통계와 무관한 힌트인지)는 develop 사용처 조사가 더 필요하다 [VERIFY].
7. 출발 DB 를 11.4 엔진의 `cubrid vacuumdb`(SA)로 먼저 비우는 선택지를 둘지. 그러면 R2 대상이 헤더 페이지뿐이지만, "엔진 바이너리 의존 0" 원칙과 충돌한다.
8. CBRD-27819 S2(10000진 NUMERIC, #471 D3·D7: 헤더 3B 유지, 데이터는 uint16 BE 10000진 자릿수 가변, 디스크 호환 번호 상향)가 11.5 에 들어가면 2.2 의 목표 형식을 바꿔야 한다. 그 경우 NUMERIC 이 든 레코드는 여전히 transform 이고 변환 비용만 커진다(이진 → 10진 자릿수 변환). 지금 S0/S1(`5852b757f`..`2f3914c1a`)은 레이아웃을 `numeric_repr` 뒤로 옮길 뿐 형식은 그대로다(#471 S0 "동작 불변").

## Sources

- develop `5b1867174`: `src/storage/slotted_page.{h,c}`, `src/storage/heap_file.{h,c}`, `src/storage/bestspace.hpp`, `src/storage/overflow_file.h`, `src/storage/storage_common.h`, `src/base/object_representation{.h,_constants.h,_sr.c}`, `src/object/object_representation.c`, `src/object/object_primitive.c`, `src/object/object_domain.c:6826-6842`, `src/object/schema_manager.c`, `src/compat/dbtype_def.h`, `src/compat/dbtype_function.i`, `src/query/vacuum.c`, `src/transaction/{mvcc.h,mvcc.c,log_lsa.hpp,log_storage.hpp}`, `src/base/system_parameter.c:5497-5505`, `src/base/intl_support.h:77-79`, `src/base/locale_lib_common.h:35`.
- release/11.4 `46212adcd`: 위 파일들의 같은 경로(`git show origin/release/11.4:<path>`), `src/query/numeric_opfunc.c:166-169,597-612`, `src/parser/csql_grammar.y:21223-21232,21508-21521`(NCHAR 생성 가능).
- 비교 방법: `git diff origin/release/11.4 5b1867174 -- <file>` 와 함수 본문 단위 비교(공백 무시). `object_representation_constants.h`·`overflow_file.{c,h}` diff 0, `spage_compact`·`spage_vacuum_slot`·`spage_check`·`spage_reclaim`·`mvcc_satisfies_vacuum`·`vacuum_heap_record_insid_and_prev_version`·`vacuum_heap_prepare_record` 본문 같음, `vacuum_heap_page`·`vacuum_heap_record` 는 bestspace 호출만 다름.
- 커밋/PR: `e84a7f6dc` CBRD-26176 #7353, `a9fca9002` CBRD-26956 #7326, `83b29b02c` CBRD-26663 #7164, `de7bc5ec2` CBRD-26006 #6486, `5ab88c6b1` CBRD-26887 #7263, `bb8f3cbda` CBRD-24156 #6420, `f1919e0d1` CBRD-26324 #6513, `1f1263217` CBRD-25862 #6443.
- CBRD-27819 survey: workspace #471, fork 커밋 `5852b757f`..`2f3914c1a`.
