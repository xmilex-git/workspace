# R1 — 11.4 vs develop 페이지 포맷 차이와 변환 모드 판정 (#473, map #472)

기준: develop = `develop@5b1867174`, 11.4 = `origin/release/11.4@46212adcd` (merge-base `13a115a0e`, 2025-05-08).
오프셋은 구조체 정의에서 나왔다. gdb `ptype /o` 교차 확인은 11.4 계열 release 빌드(`CBRD-27751-11.4@54f052d71`)와 develop optdebug 빌드의 `libcubrid.so`로 했다. 계산으로 얻은 값에는 "(계산)"을 붙였다. 16K 페이지 기준: `IO_PAGESIZE`=16384, `DB_PAGESIZE`=16384−40=16344 (storage_common.c:44,74 @develop).

## 1. 결론 (10줄)

1. 디스크 호환 레벨 상향 두 커밋은 상수만 바꾼다: CBRD-25088 `4e501e5fc` (#4802, 11.2f→11.4f), CBRD-26049 `ecb0915e4` (#6706, 11.4f→11.5f). 실제 페이지 이미지 변경은 상향 **뒤에** 레벨을 올리지 않고 들어왔다. `disk_compatibility_rules[]`는 비어 있다 (release_string.c:272-275 @develop).
2. 볼륨 헤더(`DISK_VOLUME_HEADER`, 136B), 페이지 예약 영역(`FILEIO_PAGE_RESERVED` 32B + 워터마크 8B), `PAGE_TYPE` 값, 슬롯 엔트리(`SPAGE_SLOT`), `HEAP_CHAIN`(40B), 오버플로 페이지(overflow_file.c/h는 diff 없음), OR 레코드 헤더 상수(object_representation_constants.h는 diff 없음), `_vinf`·databases.txt 형식은 **바이트 단위로 같다**.
3. 데이터 페이지 체크섬은 두 라인 모두 없다. 무결성 검사는 `prv.lsa == 워터마크 lsa` 하나뿐이다 (`fileio_page_check_corruption`, file_io.c:11970-11977 @develop, :11835 @11.4; 도입 CBRD-22231 `d81b071e8` #1187).
4. **달라진 것 ①** `HEAP_HDR_STATS` (힙 헤더 페이지 slot 0) 296B→1152B 전면 재배치. 각 힙 파일에 bestspace 페이지(1~4장, 플래그 `HEAP_PAGE_FLAG_BESTSPACE`)가 반드시 있어야 한다 — CBRD-26176 `e84a7f6dc` (#7353). develop에는 옛 헤더를 올리는 경로가 없다 (`bestspace.num_pages==0`이면 `assert_release`+에러, heap_file.c:4319-4325).
5. **달라진 것 ②** `FILE_HEADER` 216B→200B (`vpid_find_nth_last`, `first_index_find_nth_last` 삭제) — CBRD-27308 `1ea077d85` (#7792). ftab 오프셋은 헤더에 저장된 값을 쓰므로 develop이 그대로 읽는다. 다만 바이트 184..199가 `reserved0..3`으로 읽힌다.
6. **달라진 것 ③** `SPAGE_HEADER`의 `need_update_best_hint` 비트(+28 워드의 bit1)가 삭제되어 reserved로 바뀌었다 (`e84a7f6dc`). develop은 이 비트를 검사하지 않는다. 무해하지만 0으로 지우는 것을 권장한다.
7. **달라진 것 ④** 로그 헤더: `sysmeta_version`(UINT16, +102)이 `dummy3/dummy4` 자리에 들어왔다 — CBRD-26459 `9ee8bac8b` (#7773). `db_compatibility`(+64)는 11.4f→11.5f. 로그는 도구가 새로 쓰므로 페이지 문제는 아니다.
8. DWB(`<db>_dwb`)는 FILEIO_PAGE 이미지를 그냥 늘어놓은 파일이다. 부팅할 때 복구에 쓰고 지운 뒤 다시 만든다 (double_write_buffer.cpp:3200-3383). 파일이 없으면 새로 만든다. 따라서 **옮기지 않는다.**
9. 사용자 힙 데이터 페이지와 오버플로 페이지는 **그대로 복사해도 된다**. 단서 셋: (a) 페이지 LSA가 새 로그의 끝을 넘으면 안 된다 (§4 R4), (b) vacuum 잔여는 패치한다, (c) CHAR/NUMERIC 값 인코딩은 map 노트대로 repid 단위로 재인코딩한다.
10. **판정: 11.4→develop의 기본 모드는 clone/copy + patch다.** 전 페이지 transform은 필요 없다. transform 대상은 힙 파일마다 "헤더 페이지 1장 + 새 bestspace 페이지 1~4장 + 두 번째 체인 페이지의 prev 링크"뿐이다. 단 R4에서 "LSA 이어쓰기"를 쓸 수 없으면 모든 영구 페이지의 LSA 16B를 고쳐야 하고, 그러면 clone의 이점(CoW 공유)이 사라진다.

## 2. 항목별 표

### 2.1 디스크 호환 레벨과 그 뒤의 이미지 변경 커밋

| 항목 | 11.4 | develop | 커밋 / PR |
|---|---|---|---|
| `disk_compatibility_level` | 11.4f (release_string.c:105 @11.4) | 11.5f (release_string.c:105) | `4e501e5fc` #4802 (2023-11-23), `ecb0915e4` #6706 (2025-12-12). 둘 다 1줄 diff |
| CBRD-26049 범위 | — | 11.5 버전 우산 이슈 (`91be5b11f` #6162: VERSION 11.5.0) | 이미지 변경 커밋은 따로 있다 ↓ |
| 힙 헤더/bestspace | 없음 | 있음 | `e84a7f6dc` #7353 (2026-07-22) |
| FILE_HEADER 축소 | 216B | 200B | `1ea077d85` #7792 (2026-09-01) |
| 로그 헤더 `sysmeta_version` | dummy3/4 | UINT16 | `9ee8bac8b` #7773 (2026-09-22) |
| 값 인코딩 (참고, map 노트) | — | NUMERIC, CHAR | `de7bc5ec2` #6486, `83b29b02c` #7164, `a9fca9002` #7326 |

### 2.2 `FILEIO_PAGE` (모든 페이지, 페이지 오프셋 기준) — 두 라인 동일

file_io.h:165-193 @develop, :173-190 @11.4. gdb로 두 빌드 모두 확인.

| off | size | 필드 | 11.4 | develop | 비고 |
|---|---|---|---|---|---|
| 0 | 8 | `lsa` (pageid:48, offset:16 비트필드, log_lsa.hpp:36-40) | 동일 | 동일 | redo 판단에 쓰임 (log_recovery.c:531-532) |
| 8 | 4 | `pageid` | 동일 | 동일 | |
| 12 | 2 | `volid` | 동일 | 동일 | |
| 14 | 1 | `ptype` (`PAGE_TYPE` 0..13) | 동일 (storage_common.h @11.4) | 동일 (storage_common.h:151-165) | 값 바뀜 없음 |
| 15 | 1 | `pflag` (AES 0x1, ARIA 0x2, mask 0x3) | 동일 | 동일 (file_io.h:63-66) | ≠0이면 TDE 암호문 |
| 16 | 4 | `p_reserve_1` | 0 | 0 | 체크섬 아님. 0으로 초기화 (page_buffer.c:11240) |
| 20 | 4 | `p_reserve_2` | 0 | 0 | DWB가 0을 assert (double_write_buffer.cpp:2617) |
| 24 | 8 | `tde_nonce` | 동일 | 동일 | 영구 페이지: lsa. TDE 오프셋·알고리즘(CTR) 동일 (tde.c diff는 OpenSSL EVP 리팩터) |
| 32 | — | 사용자 영역 (`DB_PAGESIZE`=IO−40) | | | |
| IO−8 | 8 | `prv2.lsa` 워터마크 | 동일 | 동일 | `fileio_is_page_sane`: prv.lsa == 워터마크 (file_io.h:229-234) |

### 2.3 볼륨 헤더 (각 볼륨 page 0, 사용자 영역 +32부터) — 동일

disk_manager.c:75-111 @develop, :76 @11.4. 구조체 텍스트 diff 없음. gdb 크기 136B (두 빌드).

| off(구조체) | size | 필드 | 마이그레이션 처리 |
|---|---|---|---|
| 0 | 25 | `magic` "CUBRID/Volume" | 유지 |
| 26 | 2 | `iopagesize` | 유지 |
| 28 | 2 | `volid` | 유지 (배치 보존) |
| 30 | 1 | `db_charset` | 유지 |
| 32/36 | 4/4 | `purpose`/`type` | 유지 |
| 40..67 | 4×7 | `sect_npgs, nsect_total, nsect_max, hint_allocsect, stab_npages, stab_first_page, sys_lastpage` | 유지. 단 bestspace 페이지를 할당하면서 섹터를 새로 예약하면 STAB 비트와 `hint_allocsect`를 갱신 |
| 72 | 8 | `db_creation` | **패치**: 새 로그 헤더 값과 같게 (`log_recreate`→`disk_set_creation`, log_manager.c:8991) |
| 80 | 8 | `vol_creation` | 유지 |
| 88 | 8 | `chkpt_lsa` | **패치**: 새 로그 `chkpt_lsa` |
| 96 | 12 | `boot_hfid` | 유지 (카탈로그 재생성이 바꾸면 갱신) |
| 108..123 | 16 | `reserved0..3` | 유지 |
| 124..131 | 2×4 | `next_volid`, var 오프셋 3개 | 유지. 경로가 바뀌면 var_fields 재기록 |

### 2.4 `SPAGE_HEADER` (슬롯 페이지, 사용자 영역 +0 = 페이지 +32)

slotted_page.h:62-82 @develop, :64-84 @11.4. 크기 32B로 같다.

| off | size | 필드 | 11.4 | develop | 커밋 |
|---|---|---|---|---|---|
| 0..27 | | `num_slots, num_records, anchor_type, alignment, total_free, cont_free, offset_to_free_area, reserved1, flags` | 동일 | 동일 | |
| 28 | 4 | 비트필드 워드 bit0 `is_saving` | 동일 | 동일 | |
| 28 | (bit1) | `need_update_best_hint` | 사용 | `reserved_bits:31`에 흡수됨 | `e84a7f6dc` #7353 |

비트 위치는 x86-64 SysV ABI로 계산했다: 처음 선언한 비트필드가 LSB다. bit1 = 마스크 0x2, 페이지 오프셋 60의 32비트 LE 워드. develop은 `spage_initialize`에서 `reserved_bits=0`으로 쓰고(slotted_page.c:1080) 읽을 때 검사하지 않는다.
슬롯 i의 위치: 페이지 오프셋 `32 + DB_PAGESIZE − 4(i+1)` (slotted_page.c:4585-4586). 엔트리 `offset:14|length:14|type:4`는 같다.

### 2.5 `HEAP_CHAIN` (힙 데이터 페이지 slot 0) — 레이아웃 동일, 플래그 의미 추가

heap_file.c:274-283 @develop, :270-279 @11.4. 40B.

| off | size | 필드 | 11.4 | develop |
|---|---|---|---|---|
| 0 | 8 | `class_oid` | 동일 | 동일 |
| 8 | 8 | `prev_vpid` | 동일 | 동일 |
| 16 | 8 | `next_vpid` | 동일 | 동일 |
| 24 | 8 | `max_mvccid` | 동일 | 동일 (patch: vacuum 잔여 0이면 `MVCCID_NULL`) |
| 32 | 4 | `flags` | 0xC0000000 vacuum 상태만 (heap_file.c:241-243 @11.4) | + `0x1 BESTSPACE`, `0x2 NOT_IN_HEAP` (heap_file.c:226-230), 커밋 `e84a7f6dc` |

11.4 페이지의 bit0·bit1은 항상 0이다. develop은 0을 "일반 힙 페이지, 힙에 연결됨"으로 읽으므로 그대로 둔다.

### 2.6 `HEAP_HDR_STATS` (힙 헤더 페이지 slot 0) — 전면 변경, transform

11.4: heap_file.c:191-230 @11.4, gdb 296B. develop: heap_file.c:190-223, gdb 1152B. 커밋 `e84a7f6dc` #7353.

| 11.4 off | 11.4 필드 | develop off | develop 필드 | 변환 규칙 |
|---|---|---|---|---|
| 0 | `class_oid` (8) | 0 | `class_oid` | 복사 |
| 8 | `ovf_vfid` (8) | 8 | `ovf_vfid` | 복사 |
| 16 | `next_vpid` (8) | 16 | `next_vpid` | = bestspace `pages[0]` (체인에 끼워 넣음) |
| 68 | `estimates.last_vpid` (8) | 24 | `last_vpid` | 복사 (bestspace를 끝에 붙이면 갱신) |
| 24 | `unfill_space` (4) | 32 | `unfill_space` | 복사 |
| 28 | `estimates.num_pages` int | 36 | `num_pages` int | 복사 |
| 32 | `estimates.num_recs` int | 40 | `num_recs` uint64 | 넓힘 (추정치) |
| 36 | `estimates.recs_sumlen` float | 48 | `recs_sumlen` uint64 | 반올림 (추정치) |
| 40..67, 76..283 | best/second_best 힌트 배열 등 | — | 없음 | 버림 |
| — | — | 56 | `bestspace.num_candidates` size_t | 0 |
| — | — | 64 | `candidates[128]` × `bestspace_entry`(8B: `freespace` u16 @0, `volid` i16 @2, `pageid` i32 @4; bestspace.hpp:48-52) | null로 채움 (`set_null`) |
| — | — | 1088 | `num_shards` size_t | `bestspace_shard_count` 기본 8, 범위 1..28 (system_parameter.c:5497-5505) |
| — | — | 1096 | `num_pages` size_t | 1..4 (`MAX_SHARD_PAGE_COUNT`=4, bestspace.hpp:76) |
| — | — | 1104 | `pages[4]` VPID | 새로 할당한 bestspace 페이지, 나머지는 NULL |
| 284..295 | `reserve0..2_for_future` | 1136..1147 | `reserve0..2` | 0 |

develop은 헤더 레코드 길이를 확인하지 않고 캐스팅한다 (`heap_get_header_stats_ptr`, heap_file.c:2732-2742). 296B 레코드를 그대로 두면 이웃 레코드 바이트를 읽는다.

bestspace 페이지 수 (계산, heap_file.c:3939-3953 공식): `max_entries = 28 × 64 = 1792`, `entries_per_page = (spage_max_record_size − DB_ALIGN(40,4) − 4) / 8`.
- 16K: (16344−32−4 − 40 − 4)/8 = 2033 → **1장**
- 4K: (4056−36−40−4)/8 = 497 → **4장**

각 bestspace 페이지의 구성:
- slot 0: `HEAP_CHAIN`. flags = `BESTSPACE`, vacuum NONE.
- slot 1 (`HEAP_BESTSPACE_ENTRIES_SLOTID`, heap_file.c:247): `entries_count × 8B` REC_HOME 레코드. 첫 엔트리 = 헤더 페이지 (heap_file.c:3963-4060).

### 2.7 `FILE_HEADER` (파일 헤더 페이지, 사용자 영역 +0) — 축소, patch

11.4: file_manager.c:91-165 @11.4 (`vpid_find_nth_last` :157), gdb 216B. develop: file_manager.c:90-146, gdb 200B. 커밋 `1ea077d85` #7792.

| off | size | 11.4 | develop |
|---|---|---|---|
| 0..183 | 184 | `time_creation`…`vpid_last_user_page_ftab` | 동일 (gdb 오프셋 일치: `type` 140, `file_flags` 144, `offset_to_*_ftab` 150/152/154, `vpid_last_user_page_ftab` 176) |
| 184 | 8 | `vpid_find_nth_last` | `reserved0`, `reserved1` |
| 192 | 4 | `first_index_find_nth_last` | `reserved2` |
| 196 | 4 | `reserved0` | `reserved3` |
| 200..215 | 16 | `reserved1..3` + 패딩 | (헤더 밖, 사용되지 않는 틈) |
| `FILE_HEADER_ALIGNED_SIZE` | | 216 | 200 (file_manager.c:149) |

ftab 위치는 저장된 `offset_to_*_ftab`(11.4 파일에서는 ≥216)에서 읽는다. develop의 assert는 `≥ FILE_HEADER_ALIGNED_SIZE`(=200)이므로 통과한다 (file_manager.c:178-188). 새 파일만 200부터 놓는다 (:3539).

### 2.8 오버플로 페이지 — 동일

`git diff origin/release/11.4 develop -- src/storage/overflow_file.{c,h}`의 결과가 비어 있다 (`dbcfe381c` #7495는 11.4에서 정방향 포팅된 것).
- 첫 페이지: `next_vpid`@0(8), `length`@8(4), `data`@12.
- 나머지 페이지: `next_vpid`@0(8), `data`@8 (overflow_file.h:37-50).
- 내용은 OR 레코드다. 값 인코딩 차이는 map 노트에 정리돼 있다.

### 2.9 로그 헤더 (도구가 새로 생성, 참고)

log_storage.hpp:113-137 @develop. gdb 384B, 두 빌드 동일 크기.
- `db_compatibility`@64 float: 11.4f → 11.5f. 검사 위치: log_manager.c:1300, log_page_buffer.c:2497.
- `+102`: 11.4 `dummy3`(1B)+`dummy4`(1B) → develop `sysmeta_version` UINT16 (`9ee8bac8b` #7773). boot_sr.c:2608에서 `SYSTEM_METADATA_VERSION`과 같은지 확인한다.
- `mvcc_next_id`@80, `append_lsa`@112, `chkpt_lsa`@120, `fpageid`@104: 위치 동일.

### 2.10 볼륨 밖 파일

| 파일 | 형식 | 11.4→develop | 근거 |
|---|---|---|---|
| `<db>_vinf` | 줄마다 `"%4d %s\n"` (volid, 경로). 음수 volid는 로그·DWB 등 | 동일 | log_page_buffer.c `logpb_add_volume`, log_volids.hpp:38-57. 관련 diff 없음 |
| `databases.txt` | 형식 동일 (`DO_NOT_USE_CUBRIDENV` 분기만 삭제) | 동일 | databases_file.c diff |
| `<db>_dwb` | FILEIO_PAGE 배열, 2의 거듭제곱 장수 | 옮기지 않음 | double_write_buffer.cpp:3215-3383 (11.4: double_write_buffer.c:3110-3285) |
| `<db>_keys` | TDE 키 | TDE 볼륨은 범위 밖 | map 노트 |

## 3. Rust 도구가 구현할 규칙 (기계적 검사)

- **R0 사전 거부.** 아래 중 하나라도 맞으면 거부한다.
  - 로그 헤더 `db_compatibility != 11.4f` 또는 `is_shutdown == false`
  - 어느 볼륨이든 `iopagesize`가 로그 헤더 `db_iopagesize`와 다름
  - 영구 페이지 하나라도 `pflag & 0x3 != 0` (TDE, 범위 밖)
- **R1 페이지 무결성.** 읽는 모든 페이지에서 `bytes[0..8] == bytes[IO−8..IO]`인지 본다. 다르면 출발 DB의 손상으로 보고하고 그 페이지를 transform하지 않는다. 체크섬 필드는 없으므로 계산하지 않는다.
- **R2 PAGE_TYPE 라우팅.** `ptype`(off 14) 값은 두 라인이 같다. PAGE_HEAP이면서 slot0 길이 == 40이면 데이터 페이지(patch 대상)다. slot0 길이 == 296이면 힙 헤더 페이지(R5)다. PAGE_OVERFLOW는 copy한다. PAGE_FTAB 중 파일 헤더 페이지는 R6으로 보낸다. PAGE_BTREE, PAGE_CATALOG, 카탈로그 힙은 재생성 대상이므로 버린다.
- **R3 SPAGE 정리.** 슬롯 페이지마다 페이지 오프셋 60의 u32에서 bit1(0x2)을 지운다. 권장 사항이며, 남겨도 develop은 읽지 않는다.
- **R4 LSA 규칙.** 도착 DB의 모든 영구 페이지는 `page_lsa ≤ 새 로그 append_lsa`를 만족해야 한다. 근거는 두 가지다: WAL assert (log_page_buffer.c:4256), redo는 `rcv_lsa ≤ page_lsa`이면 건너뛰고 `page_lsa ≤ end_redo_lsa`를 assert한다 (log_recovery.c:531-532). 방법은 둘 중 하나다.
  - (a) 엔진 `log_recreate`처럼 모든 페이지의 `prv.lsa`와 워터마크를 NULL_LSA로 다시 쓴다 (log_manager.c:8954-8988, `fileio_reset_volume` file_io.c:2886-2931). 전 페이지 쓰기다.
  - (b) 새 로그의 LSA 공간을 출발 로그 헤더 `append_lsa`의 다음 페이지에서 시작한다. WAL 때문에 출발 페이지 LSA는 모두 그보다 작다. 손대지 않은 페이지는 clone 그대로 유지된다.
  - 어느 쪽이든 도구가 수정한 페이지에는 prv.lsa와 워터마크를 같은 값으로 쓴다 (R1 불변식).
- **R5 힙 헤더 transform (힙 파일마다).**
  1. 296B 헤더 레코드를 §2.6 표대로 1152B로 바꾼다.
  2. 헤더 페이지의 `total_free`(압축 후)가 `1152 − 296 = 856`B(계산, 4B 정렬에서 그대로) 이상이어야 한다. 모자라면 헤더 페이지의 사용자 레코드를 REC_RELOCATION(같은 슬롯) → 다른 페이지의 REC_NEWHOME으로 내보낸다. 이렇게 하면 OID는 보존된다.
  3. 힙 파일 안에 bestspace 페이지 N장(16K=1, 4K=4)을 할당한다. 파일의 partial-sector 비트맵에 빈 페이지가 있으면 먼저 쓰고, 없으면 섹터를 예약한다 (볼륨 STAB와 FILE_HEADER 카운트 갱신).
  4. 체인을 `header → bs[0] → … → bs[N−1] → 옛 next_vpid`로 다시 잇는다 (develop 생성 순서와 같다, heap_file.c:3985-4002). 옛 2번째 페이지 slot0의 `prev_vpid`를 패치한다.
- **R6 FILE_HEADER patch.** 사용자 영역 오프셋 184..199(페이지 216..231)를 0으로 쓴다. develop의 `reserved0..3=0` 불변식(file_manager.c:898-901)을 맞추는 것이다. 다른 필드와 ftab 오프셋은 유지한다.
- **R7 볼륨 헤더 patch.** `db_creation`(+72)과 `chkpt_lsa`(+88)를 새 로그 헤더 값으로 쓴다. 나머지는 유지한다.
- **R8 DWB와 로그.** `_dwb`, `_lgat`, `_lgar*`, `_lginf`, `_bkvinf`는 옮기지 않는다. 로그 헤더는 develop 레이아웃으로 생성한다: `db_compatibility=11.5f`, `sysmeta_version=SYSTEM_METADATA_VERSION`, `mvcc_next_id`는 새 값.
- **R9 모드 결정.**
  - 데이터 볼륨: clone(reflink) 또는 copy를 한 뒤 R3/R5/R6/R7과 vacuum·인코딩 patch를 제자리에서 한다.
  - transform 페이지 수 = Σ힙 파일 × (1 + N + 1).
  - R4(a)를 쓰면 모든 페이지가 patch 대상이 된다. 그러면 clone 대신 "copy 중 인라인 패치" 1패스가 낫다.

## 4. Open questions

1. R4(b)를 엔진이 받아들이는가? 새 로그의 `fpageid`/`append_lsa`를 큰 값에서 시작하는 경우다. vacuum 블록 id (`vacuum_last_blockid`)와 `does_block_need_vacuum` 초기값과의 정합을 확인해야 한다. 로그 헤더를 다루는 티켓에서 develop 런타임으로 검증할 필요가 있다.
2. bestspace 엔트리를 null로 두면 develop이 기존 힙의 빈 공간을 다시 쓰는가, 아니면 새 페이지만 할당해 파일이 커지는가? `heap_build_bestspace`의 동작을 읽는 것과 런타임 확인이 필요하다. 대안은 Rust가 패스 중에 측정한 free space로 엔트리를 채우는 것이다.
3. bestspace 페이지를 체인 중간이 아니라 끝에 붙여도 develop 스캔/compact/`heap_update_bestspace_chain`이 올바른가? (R5.4는 생성 순서를 그대로 따르는 보수적 선택)
4. `FILE_HEADER`의 216..231 틈을 남겨도 될까? 파일 테이블을 재구성하는 develop 경로가 `FILE_HEADER_ALIGNED_SIZE`를 다시 계산하는지는 `callers`로 전수 확인하지 않았다.
5. 11.4 힙 헤더 페이지가 꽉 찬 경우(R5.2 relocation)가 실제 기준 DB에서 얼마나 자주 생기는지 측정이 필요하다.
6. CBRD-26049(#6706)의 JIRA 본문에 이 목록 밖의 의도된 변경이 있는지는 JIRA에 접근할 수 없어 미확인이다. 소스 diff에서는 위 항목만 찾았다. btree·카탈로그는 재생성 대상이라 비교하지 않았다.

## 5. Sources

- 레벨 상향: `ecb0915e4` (#6706), `4e501e5fc` (#4802), `91be5b11f` (#6162), `37720d8ed` (#2495), `5b4853145` (#3506); src/base/release_string.c:105, 272-275, 293-330 @develop.
- 이미지 변경: `e84a7f6dc` (#7353, CBRD-26176), `1ea077d85` (#7792, CBRD-27308), `9ee8bac8b` (#7773, CBRD-26459), `d81b071e8` (#1187, CBRD-22231).
- 페이지/볼륨: src/storage/file_io.h:62-66, 165-234; file_io.c:2886-2931, 11970-11977; disk_manager.c:75-111; slotted_page.h:62-90; slotted_page.c:1080, 4585-4586; storage_common.c:44-74; storage_common.h:151-165 (모두 @develop) 및 같은 파일 @origin/release/11.4.
- 힙: heap_file.c:190-247, 274-283, 2732-2742, 2815-2832, 3742-3744, 3900-4060, 4319-4325 @develop; heap_file.c:183-243, 270-279, 5122-5124 @11.4; bestspace.hpp:48-82.
- 파일 관리자: file_manager.c:90-188, 894-901, 3522-3606 @develop; file_manager.c:91-168 @11.4.
- 오버플로: overflow_file.h:37-50 (diff 없음).
- 로그/복구: log_storage.hpp:113-137; log_manager.c:1300, 8925-9010; log_page_buffer.c:2497, 4239-4266; log_recovery.c:504-532; boot_sr.c:2608.
- DWB: double_write_buffer.cpp:3200-3383 @develop; double_write_buffer.c:3110-3285 @11.4.
- gdb `ptype /o`: CBRD-27751-11.4 release `libcubrid.so` (11.4 계열 `54f052d71`), develop optdebug `libcubrid.so`. 대상: fileio_page_reserved, disk_volume_header, spage_header, heap_hdr_stats, heap_chain, file_header, log_header.
