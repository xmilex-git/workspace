# R5 새 DB 최소 파일 집합 — 볼륨·파일 트래커·섹터 테이블·로그 헤더·vacuum data·volinfo (#477, map #472)

기준: develop `5b1867174`, release/11.4 `46212adcd` (`~/dev/cubrid-worktree/develop`). 표기 `D:` = develop 파일:줄, `R114:` = `origin/release/11.4` 파일:줄. 오프셋 열은 **페이지 안 바이트 오프셋**이며, 구조체 정의를 옮겨 적은 C 프로그램(`offsetof`, x86-64 gcc)으로 **계산한 값**이다(엔진 빌드 산출물에서 읽은 값이 아님). 페이지 크기는 기본값 IO 16 KiB 기준이다.

## 요약 (질문에 대한 답)

1. 11.4→develop 사이에 바뀐 디스크 구조는 이 티켓 범위에서 **세 가지**다. (a) 로그 헤더 바이트 102–103(`dummy3/dummy4` → `UINT16 sysmeta_version`, #7773), (b) 로그 헤더 `db_compatibility` 11.4f→11.5f(#6706), (c) `FILE_HEADER` 크기 216→200 B(`vpid_find_nth_last`/`first_index_find_nth_last` 삭제, #7792). 볼륨 헤더, 섹터 테이블, 확장 데이터(extdata), 트래커 항목, vacuum data와 dropped files 페이지, `BOOT_DB_PARM`, `FILEIO_PAGE` 예약 영역, `PAGE_TYPE`/`FILE_TYPE` 열거값은 두 줄기에서 같다.
2. (c)는 **이미 있는 11.4 파일 헤더 페이지를 고치지 않아도 된다.** 표 위치가 헤더 안의 `offset_to_*_ftab` 값으로 저장되어 있고, develop은 그 값이 `FILE_HEADER_ALIGNED_SIZE`(200) 이상인지만 검사한다. develop의 `reserved0..3`(184–199)는 11.4의 캐시 필드와 겹치지만 초기화할 때 말고는 아무도 읽지 않는다. Rust가 **새로 만드는** 파일만 develop 레이아웃(헤더 200 B, 첫 표는 오프셋 200)을 따르면 된다.
3. 도착 DB를 새 로그로 부팅하는 길은 엔진에 이미 있다. `copydb`의 `logpb_copy_database`가 하는 일이 그대로 명세다. 헤더 페이지(물리 0)에 `logpb_initialize_header` 값을 쓰고 `was_copied=true`와 `mvcc_next_id`(출발 값)를 넣는다. 물리 1 페이지에는 `LOG_END_OF_LOG` 레코드 하나만 둔다. 나머지 공간은 sparse로 둔다. 모든 볼륨 헤더의 `db_creation`과 `chkpt_lsa`를 새 로그 값으로 맞추고, 모든 페이지 LSA를 NULL로 리셋한다. 첫 부팅 때 `boot_after_copydb`가 vacuum data를 초기화하고 `was_copied`를 지운다.
4. 그러므로 최소 파일은 **볼륨들 + `_lgat` 하나**다. `_vinf`는 없거나 맞지 않으면 볼륨 링크를 따라 재생성된다. `_lginf`는 덧붙이기 전용 텍스트이고, 부팅 때 읽는 곳은 archive 번호 추측(archive가 없으면 쓰이지 않음)뿐이다. `_dwb`는 없으면 건너뛰고 다시 만든다. `_bkvinf`는 백업용이다. `_keys`는 TDE 키 heap과 짝이므로 그대로 복사한다.
5. 출발 쪽 `_dwb`와 `_lgar*`, `_lgar_t`는 **도착에 두면 안 된다**. 남아 있는 DWB는 복구 때 페이지를 옛 이미지로 덮어쓴다.
6. 페이지 LSA 정책은 둘 중 하나를 골라야 한다. (A) copydb와 같게 모든 페이지의 `prv.lsa`와 워터마크를 NULL로 둔다. 모든 페이지에 쓰므로 clone 모드와 충돌한다. (B) 페이지는 손대지 않고 새 로그의 `fpageid`를 출발 로그 `append_lsa.pageid`+1로 시작한다. (B)는 엔진의 `PRM_ID_FIRST_LOG_PAGEID`(QA 전용) 경로가 근거지만 release 경로로 검증된 적은 없다([VERIFY]).
7. 섹터 테이블은 볼륨마다 페이지 1부터 **섹터당 1비트**(UINT64 단위, LSB가 낮은 sectid)인 비트맵이다. 사용 중인 섹터 수는 디스크 어디에도 저장되지 않는다. 부팅 때 비트를 세어 캐시를 만든다. 파일 해제는 "그 파일의 partial/full 표에 있는 모든 VSID의 비트를 지우고, 트래커에서 항목을 빼고, 페이지 `ptype=PAGE_UNKNOWN`으로 둔다"이다. 할당은 그 반대에 `file_create`의 헤더 레이아웃을 더한 것이다.
8. 파일 트래커는 트래커 파일의 sticky first page에서 시작하는 extdata 사슬이다. 항목은 16 B `{fileid, volid, type, metadata}`이고 `(volid, fileid)` 오름차순이다. 트래커 파일 자신은 등록되지 않는다.
9. `sysmeta_version`은 반드시 1로 둔다. 0이면 부팅 때 `ER_SYSMETA_UPGRADE_REQUIRED`가 난다. `db_compatibility`가 11.5f가 아니면 `ER_LOG_INCOMPATIBLE_DATABASE`가 난다. `db_release`는 "11.5.0"이다.
10. 엔진을 실행해 본 확인은 없다. 이 문서의 결론은 모두 소스를 정적으로 읽어 얻은 것이고, (B)와 sparse 로그를 쓴 첫 부팅은 smoke가 필요하다(Open questions).

## 1. createdb가 만드는 것 (develop)

`boot_create_all_volumes`(D: src/transaction/boot_sr.c:4916-5195)의 순서는 다음과 같다. 11.4와 비교한 diff에서 이 함수에 생성 단계가 추가되거나 빠진 것은 없다. boot_sr.c diff에서 생성 경로와 관련된 변경은 재시작 때의 `sysmeta_version` 검사뿐이다.

| 순서 | 무엇 | 코드 |
|---|---|---|
| 1 | active log `_lgat` 포맷, 헤더와 첫 append 페이지 기록, `_vinf` 생성(-5, -4 lginf, -3 bkvinf, -2 lgat), `_lginf` 생성 | `log_create_internal` D: log_manager.c:837-992 |
| 2 | DWB `_dwb`(log_path) | boot_sr.c:4965 `dwb_create` |
| 3 | 첫 볼륨 포맷: 볼륨 헤더(page 0), 섹터 테이블(page 1..`sys_lastpage`), 시스템 섹터 비트 설정 | `disk_format` D: disk_manager.c:512-814, `disk_stab_init` :4930-5013 |
| 4 | `_vinf`에 `0 <vol>` 추가 | boot_sr.c:4978 |
| 5 | 파일 트래커(FILE_TRACKER, 1 page, sticky first page = 트래커 extdata) | `file_tracker_create` D: file_manager.c:9927-9966 |
| 6 | heap: boot parm(`hfid`), root class(`rootclass_hfid`), TDE keyinfo | boot_sr.c:5014 (tracker), 5020-5037 (heap) |
| 7 | classname ehash, 카탈로그(`ctid`) | boot_sr.c:5056, 5069 |
| 8 | boot parm 레코드 삽입, 볼륨 헤더 `boot_hfid` 설정 | boot_sr.c:5074-5091 |
| 9 | vacuum data 파일(1 page, `data[0].blockid=0`), dropped files 파일(sticky 1 page) | `vacuum_create_file_for_vacuum_data` D: vacuum.c:4459-4501, `…_dropped_files` :4558-4596 |
| 10 | 메타클래스와 시스템 카탈로그 설치, TDE 초기화, flush, checkpoint | boot_sr.c:5153-5169 |

`BOOT_DB_PARM`(D: boot_sr.c:122-142 = R114: boot_sr.c:113-132, 필드 동일)이 trk/vacuum/dropped files의 VFID를 들고 있으므로, Rust는 이 레코드의 VFID들을 그대로 유지한다.

## 2. 바이트 레이아웃

### 2.1 데이터 페이지 공통 예약 영역 `FILEIO_PAGE_RESERVED` (D: src/storage/file_io.h:166-193, 두 줄기 동일)

| off | size | 필드 | 비고 |
|---|---|---|---|
| 0 | 8 | `lsa` (LOG_LSA: pageid:48, offset:16, int64 비트필드) | |
| 8 | 4 | `pageid` | |
| 12 | 2 | `volid` | |
| 14 | 1 | `ptype` (PAGE_TYPE) | 0 UNKNOWN, 1 FTAB, 2 HEAP, 3 VOLHEADER, 4 VOLBITMAP, …, 12 DROPPED_FILES, 13 VACUUM_DATA (D: storage_common.h:149-166, R114 동일) |
| 15 | 1 | `pflag` | TDE 비트 0x1/0x2 |
| 16 | 4+4 | `p_reserve_1/2` | |
| 24 | 8 | `tde_nonce` | perm 페이지는 LSA |
| IO-8 | 8 | 워터마크 `prv2.lsa` | `prv.lsa`의 복제 |

DB 페이지 영역은 io 오프셋 32부터 시작하고 길이는 `DB_PAGESIZE = IO_PAGESIZE - 40`이다(D: storage_common.c:44,74; 16K에서 16344, 계산값). 데이터 페이지에는 체크섬이 없다. 손상 판정은 `prv.lsa == 워터마크`인지로만 한다(`fileio_page_check_corruption` → `fileio_is_page_sane`, D: file_io.c:11970-11977).

### 2.2 볼륨 헤더 `DISK_VOLUME_HEADER` (D: disk_manager.c:74-110; disk_manager.c의 11.4→develop diff에 구조체 변경 없음)

| DB off | io off | size | 필드 | createdb 값 |
|---|---|---|---|---|
| 0 | 32 | 25 | `magic` | "CUBRID/Volume" |
| 26 | 58 | 2 | `iopagesize` | IO_PAGESIZE |
| 28 | 60 | 2 | `volid` | |
| 30 | 62 | 1 | `db_charset` | |
| 32 | 64 | 4 | `purpose` | 0 = PERMANENT_DATA (D: dbtype_def.h:200) |
| 36 | 68 | 4 | `type` | |
| 40 | 72 | 4 | `sect_npgs` | 64 (`DISK_SECTOR_NPAGES`, storage_common.h:109) |
| 44 | 76 | 4 | `nsect_total` | |
| 48 | 80 | 4 | `nsect_max` | |
| 52 | 84 | 4 | `hint_allocsect` | NULL_SECTID (힌트) |
| 56 | 88 | 4 | `stab_npages` | `ceil(nsect_max / (DB_PAGESIZE*8))` |
| 60 | 92 | 4 | `stab_first_page` | 1 |
| 64 | 96 | 4 | `sys_lastpage` | `stab_first_page + stab_npages - 1` (D: disk_manager.c:3166-3171) |
| 72 | 104 | 8 | `db_creation` | **로그 헤더 `db_creation`과 같아야 함** |
| 80 | 112 | 8 | `vol_creation` | |
| 88 | 120 | 8 | `chkpt_lsa` | 로그 헤더 `chkpt_lsa` |
| 96 | 128 | 12 | `boot_hfid` | volume 0만 의미 있음 |
| 108 | 140 | 16 | `reserved0..3` | 0 |
| 124 | 156 | 2 | `next_volid` | 다음 perm 볼륨, 마지막은 NULL_VOLID |
| 126–130 | 158–162 | 2×3 | `offset_to_vol_fullname / next_vol_fullname / vol_remarks` | `var_fields` 기준 오프셋 |
| 132 | 164 | … | `var_fields` | NUL로 끝나는 문자열 세 개 |

### 2.3 섹터 테이블 (STAB) (D: disk_manager.c:194-231, 3263-3279, 4930-5013)

- 단위는 `UINT64`이고, 한 페이지에 `DB_PAGESIZE/8` 단위(16K에서 2043), 즉 `DB_PAGESIZE*8`비트(16K에서 130752 섹터, 계산값)가 들어간다.
- sectid `s`의 위치: 페이지 `stab_first_page + s / (DB_PAGESIZE*8)`, 단위 `(s % bits_per_page) / 64`(io 오프셋 32 + 단위×8, little-endian), 비트 `s % 64`(`bit64_is_set`: `x & (1<<off)`, D: src/base/bit.c:574-578).
- 포맷 직후에는 `SECTOR_FROM_PAGEID(sys_lastpage)+1`개 시스템 섹터의 비트가 켜져 있다(`disk_stab_set_bits_contiguous` :3817-3834). 페이지 `ptype=PAGE_VOLBITMAP`.
- 사용 중인 섹터 수는 디스크에 저장하지 않는다. 부팅 때 `disk_volume_boot`가 비트를 세어 `nsect_free`를 만든다(D: disk_manager.c:2484-2491, `disk_cache_load_volume` :2567-2618).

### 2.4 `FILE_HEADER` — 11.4와 develop이 다른 유일한 페이지 구조

| off | size | 필드 | 11.4 | develop |
|---|---|---|---|---|
| 0 | 8 | `time_creation` | = | = |
| 8 | 8 | `self` (VFID) | = | = |
| 16 | 24 | `tablespace` | = | = |
| 40 | 64 | `descriptor` (union, `FILE_DESCRIPTORS_SIZE` 64) | = | = |
| 104–120 | 4×5 | `n_page_total/user/ftab/free/mark_delete` | = | = |
| 124–136 | 4×4 | `n_sector_total/partial/full/empty` | = | = |
| 140 | 4 | `type` (FILE_TYPE; 0 TRACKER, 1 HEAP, 2 HEAP_REUSE_SLOTS, … 10 VACUUM_DATA, 12 TEMP; 두 줄기 동일) | = | = |
| 144 | 4 | `file_flags` (0x1 numerable, 0x2 temp, 0x4/0x8 TDE) | = | = |
| 148 | 2 | `volid_last_expand` | = | = |
| 150/152/154 | 2×3 | `offset_to_partial_ftab / full / user_page` | 저장값 | 저장값 |
| 156 | 8 | `vpid_sticky_first` | = | = |
| 164 | 8 | `vpid_last_temp_alloc` | = | = |
| 172 | 4 | `offset_to_last_temp_alloc` | = | = |
| 176 | 8 | `vpid_last_user_page_ftab` | = | = |
| 184 | 8 | | `vpid_find_nth_last` | `reserved0`,`reserved1` |
| 192 | 4 | | `first_index_find_nth_last` | `reserved2` |
| 196 | 4 | | `reserved0` | `reserved3` |
| 200–215 | 16 | | `reserved1..3` + 패딩 | (헤더 끝) |
| | | `sizeof` / `FILE_HEADER_ALIGNED_SIZE` | **216** | **200** |

출처: D: file_manager.c:88-149, R114: file_manager.c:91-165. 변경 커밋은 `1ea077d85` [CBRD-27308] (CUBRID/cubrid#7792, 2026-09-01 merge)이다.

develop에서 이 차이가 무해한 근거: 표 포인터 매크로는 `offset_to_*_ftab >= FILE_HEADER_ALIGNED_SIZE`라는 assert만 걸고, 표를 찾을 때는 저장된 오프셋을 쓴다(D: file_manager.c:176-189). `reserved0..3`는 초기화 두 곳(:898-901, :3526-3529) 말고는 읽는 곳이 없다(rg). 11.4가 `vpid_find_nth_last`를 쓰는 조건은 `FILE_TEMP` 임시 파일뿐이었다(R114 `FILE_CACHE_LAST_FIND_NTH`; diff에서 삭제된 정의 확인).

`file_create`의 표 배치(D: file_manager.c:3539-3600, develop 값은 계산값):

| 파일 종류 | partial 표 | full 표 | user page 표 |
|---|---|---|---|
| perm, non-numerable (heap, btree, catalog 등) | off 200, `max_size` 8048 → 503 항목(16 B) | off 8264, `max_size` 8064 → 1008 VSID(8 B) | – |
| perm, numerable (ehash) | off 200, (DB_PAGESIZE-200)/32 | 그다음, 같은 크기 | 나머지 |
| 11.4 non-numerable (참고) | off 216, 503 항목 | off 8280, 1006 VSID | – |

`file_extdata_init`: `max_size = ALIGN_BELOW(size - 16, item)`, 8 정렬이 안 되면 한 항목 줄인다. `file_extdata_max_size = 16 + max_size`(D: :1468-1499).

### 2.5 extdata 헤더, partial sector, 트래커 항목

| 구조 | off/size | 필드 |
|---|---|---|
| `FILE_EXTENSIBLE_DATA` (D: file_manager.c:209-218) | 0/8 `vpid_next`, 8/2 `max_size`, 10/2 `size_of_item`, 12/2 `n_items`; 정렬 크기 16, 항목은 16부터 | |
| `FILE_PARTIAL_SECTOR` (D: file_manager.h:162-168, 11.4에서는 .c에 있었고 내용 동일) | 0/8 `VSID{sectid, volid}`, 8/8 `page_bitmap`(비트 i = 섹터 i번째 페이지 할당) | |
| full 표 항목 | 8 B `VSID` | |
| `FILE_TRACK_ITEM` (D: file_manager.c:490-499) | 0/4 `fileid`, 4/2 `volid`, 6/2 `type`, 8/8 `metadata`(heap: `is_marked_deleted` + 7 B) | 정렬 `(volid, fileid)` (`file_compare_track_items` :2983-2997) |

트래커: 트래커 파일의 sticky first page 전체가 extdata다(`file_tracker_init_page` :10003-10014, `item=16`, `max_size=DB_PAGESIZE`). 넘치면 새 페이지를 `vpid_next`로 잇는다(:10104-10138). 삽입은 정렬 위치에 한다(:10145-10156). `file_create`는 트래커 자신과 임시 파일을 빼고 모든 파일을 등록한다(:3812-3820). 해제 때 페이지가 합쳐지면 빈 페이지를 dealloc한다(`file_tracker_unregister` :10179-10242).

### 2.6 vacuum data 페이지와 dropped files 페이지 (D: vacuum.c:105-214, 581-611; vacuum.c diff에 레이아웃 변경 없음)

| 페이지 | off/size | 필드 |
|---|---|---|
| `VACUUM_DATA_PAGE` | 0/8 `next_page`, 8/2 `index_unvacuumed`, 10/2 `index_free`, 16/32×n `data[]` | 항목 32 B: `blockid`(8, 플래그 포함), `start_lsa`(8), `oldest_visible_mvccid`(8), `newest_mvccid`(8) |
| `VACUUM_DROPPED_FILES_PAGE` | 0/8 `next_page`, 8/2 `n_dropped_files`, 16/16×n | 항목: `VFID`(8) + `mvccid`(8) |

데이터가 비어 있어도 `data[0].blockid`는 "마지막 blockid"를 담는다. createdb는 0, copydb 후 첫 부팅은 `VACUUM_NULL_LOG_BLOCKID`(-1)을 쓴다(D: vacuum.c:8004-8011, 7966-8001; log_common_impl.h:54). 첫 페이지 VPID는 파일 헤더 `descriptor.vacuum_data.vpid_first`(헤더 off 40)에 있다.

### 2.7 active log `_lgat`

물리 페이지 0 = 헤더(logical -9), 물리 1.. = logical `fpageid`부터 시작하는 순환 영역이다(`logpb_to_physical_pageid` D: log_page_buffer.c:5026-5059). 페이지 크기는 `db_logpagesize`.

**로그 페이지 헤더 `LOG_HDRPAGE`** (D: log_storage.hpp:62-71, 동일): 0/8 `logical_pageid`, 8/2 `offset`, 10/2 `flags`, 12/4 `checksum`; `area`는 16부터.
체크섬(D: log_page_buffer.c:455-494): `checksum` 칸을 0으로 둔 페이지에서 4096 B 블록마다 앞 16 B와 뒤 16 B를 차례로 이어 붙이고, 그 위에서 CRC-32(poly 0x04C11DB7, init/xorout 0xFFFFFFFF, reflect in/out, D: src/base/CRC.h:1567-1571)를 계산한다.

**`LOG_HEADER`** (`area`부터, 파일 오프셋 = 16 + off; D: log_storage.hpp:113-169, R114: 113-170)

| off | size | 필드 | 11.4 | develop | 새 로그에 쓸 값 (근거) |
|---|---|---|---|---|---|
| 0 | 25 | `magic` | = | = | "CUBRID/LogActive" |
| 28 | 4 | `cdc_arv_num_to_keep` | = | = | 0 (`LOG_HDR_CDC_ARV_NUM_RESET`) |
| 32 | 8 | `db_creation` | = | = | 새 값, 모든 볼륨 헤더 off 72와 같게 |
| 40 | 8 | `vol_creation` | = | = | time |
| 48 | 15 | `db_release` | "11.4.x" | "11.5.0" | "11.5.0" (CMakeLists.txt:181, VERSION) |
| 64 | 4 | `db_compatibility` | 11.4f = `66 66 36 41` | **11.5f = `00 00 38 41`** | 11.5f (D: release_string.c:105 / R114: 105, #6706) |
| 68/70 | 2/2 | `db_iopagesize/db_logpagesize` | = | = | 출발 값 |
| 72 | 1 | `is_shutdown` | = | = | 1 |
| 76 | 4 | `next_trid` | = | = | 1 |
| 80 | 8 | `mvcc_next_id` | = | = | **출발 값** (copydb `logpb_copy_log_header` D: log_page_buffer.c:1459) |
| 88/92 | 4/4 | `avg_ntrans/avg_nlocks` | = | = | 100 / 977 (log_impl.h:117-118) |
| 96 | 4 | `npages` | = | = | 파일 페이지 수 - 1 |
| 100 | 1 | `db_charset` | = | = | 출발 값 |
| 101 | 1 | `was_copied` | = | = | 1 (규칙 L5) |
| 102 | 2 | | `dummy3,dummy4` = 0 | **`sysmeta_version`** | **1** (`SYSTEM_METADATA_VERSION`, D: object/system_metadata_version.h:32; `9ee8bac8b` #7773) |
| 104 | 8 | `fpageid` | = | = | 0 (A) 또는 F (B) |
| 112 | 8 | `append_lsa` (develop: `LOG_LSA_ATOMIC`, 레이아웃 같음은 static_assert로 보장, log_lsa.hpp:89-92, #7875) | = | = | (fpageid, 0) |
| 120 | 8 | `chkpt_lsa` | = | = | = append_lsa |
| 128 | 8 | `nxarv_pageid` | = | = | fpageid |
| 136 | 4 | `nxarv_phy_pageid` | = | = | 1 |
| 140 | 4 | `nxarv_num` | = | = | 0 |
| 144/148 | 4/4 | `last_arv_num_for_syscrashes/last_deleted_arv_num` | = | = | -1 / -1 |
| 152–175 | 8×3 | `bkup_level0..2_lsa` | = | = | NULL LSA |
| 176 | 18 | `prefix_name` | = | = | DB 이름(다르면 notification만, log_manager.c:1242-1250) |
| 194 | 1 | `has_logging_been_skipped` | = | = | 0 |
| 200 | 8 | `vacuum_last_blockid` | = | = | 0 |
| 208 | 4 | `perm_status_obsolete` | = | = | 0 |
| 216 | 96 | `bkinfo[3]` | = | = | 0 |
| 312/316 | 4/4 | `ha_server_state/ha_file_status` | = | = | 0 / -1 |
| 320 | 8 | `eof_lsa` | = | = | NULL |
| 328 | 8 | `smallest_lsa_at_last_chkpt` | = | = | NULL |
| 336 | 8 | `mvcc_op_log_lsa` | = | = | NULL |
| 344/352 | 8/8 | `oldest_visible_mvccid/newest_block_mvccid` | = | = | 4 (`MVCCID_FIRST`) / 0 (`logpb_vacuum_reset_log_header_cache` :12155-12162) |
| 360/368 | 8/8 | `ha_promotion_time/db_restore_time` | = | = | 0 |
| 376–378 | 1×3 | `mark_will_del/does_block_need_vacuum/was_active_log_reset` | = | = | 0 |
| | | `sizeof` | 384 | 384 | |

초기값 출처는 `logpb_initialize_header`(D: log_page_buffer.c:1335-1423)다. NULL LSA = pageid -1, offset -1(`NULL_LOG_PAGEID`, `NULL_LOG_OFFSET`, log_lsa.hpp:113-114; 비트필드이므로 8바이트 모두 0xFF).

**첫 append 페이지** (물리 1, copydb와 같음; D: log_page_buffer.c:10205-10230): `logical_pageid = fpageid`, `offset = NULL_OFFSET(-1)`, `flags = 0`. `area` 오프셋 0에 `LOG_RECORD_HEADER`(32 B: `prev_tranlsa`, `back_lsa`, `forw_lsa`는 모두 NULL, off 24 `trid = 1`, off 28 `type = 35 = LOG_END_OF_LOG`; D: log_record.hpp:108,145-153)를 두고 체크섬을 넣는다. 그 밖의 페이지는 쓰지 않는다. copydb도 `fileio_format(..., is_sweep_clean=false)`라 마지막 페이지만 기록하고 나머지는 구멍으로 둔다(D: file_io.c:2309-2466, sweep 분기 2429-2438).

### 2.8 볼륨 밖 보조 파일

| 파일 | 형식 | 부팅에 필요? | 근거 |
|---|---|---|---|
| `<db>_vinf` | 텍스트 줄 `"%4d %s\n"` (volid 폭 4). createdb 순서: -5 vinf, -4 lginf, -3 bkvinf, -2 lgat, 0 vol, 이후 볼륨 1.. | 아니오. 없거나 개수가 `nvols`와 다르면 디스크 링크를 따라 다시 만든다 | D: log_page_buffer.c:4789, 4900; boot_sr.c:1066-1131 |
| `<db>_lginf` | `"Time: mm/dd/yy HH:MM:SS.mmm - "` + 메시지, 덧붙이기 전용 | 아니오. 읽는 곳은 archive 번호 추측(`logpb_get_guess_archive_num`)뿐 | D: log_comm.c:207-269; log_page_buffer.c:4635-4690 |
| `<db>_bkvinf` | 백업 정보 | 아니오 | |
| `<db>_dwb` | DWB | 아니오. 없으면 복구를 건너뛰고 다시 만든다. **출발 것을 두면 안 됨** | D: double_write_buffer.cpp:3215 |
| `<db>_keys` | TDE 마스터 키 | TDE 키 heap(`tde_keyinfo_hfid`)과 짝. copydb도 복사한다(실패해도 계속) | D: log_page_buffer.c:10132; tde.h/tde.c 11.4→develop 구조 diff 없음 |
| `<db>_lgar*`, `_lgar_t` | archive | 두지 않음 (`nxarv_num=0`) | |

## 3. Rust가 구현할 규칙 (기계적 검사)

**출발 전제 검사**
- P1. 출발 로그 헤더 `is_shutdown == 1`, `db_compatibility == 11.4f`, `sysmeta`(102–103) `== 0`. 아니면 거부한다.
- P2. 출발 vacuum이 끝났는지는 R4에서 버리고 다시 쓰므로 검사하지 않는다. 대신 페이지 쪽 vacuum 잔여는 map의 patch 단계가 0으로 만든다는 것을 전제로 한다.

**로그 (L)**
- L1. `_lgat` 크기 = `npages_total × db_logpagesize`(출발 `npages + 1` 재사용 권장). 물리 0에 §2.7 헤더 값, 물리 1에 EOF 레코드를 쓰고 두 페이지 모두 체크섬을 계산한다. 나머지는 sparse로 둔다.
- L2. `db_compatibility` 바이트 = `00 00 38 41`, `sysmeta_version`(파일 오프셋 118) = `01 00`, `db_release` = "11.5.0\0".
- L3. `mvcc_next_id` = 출발 헤더 off 80 값(되돌리지 않음).
- L4. `db_creation` 하나를 정해 로그 off 32와 **모든** perm 볼륨 헤더 io off 104에 쓴다. 볼륨 헤더 io off 120(`chkpt_lsa`)에는 로그 `chkpt_lsa`를 쓴다. `log_initialize`가 마운트된 모든 볼륨의 `db_creation`을 비교한다(D: log_manager.c:1391-1400).
- L5. `was_copied = 1`. 첫 부팅 때 `boot_after_copydb` → `vacuum_reset_data_after_copydb`가 vacuum data 첫 페이지를 `blockid=-1`로 다시 만들고 플래그를 지운다(D: boot_sr.c:6200-6230, vacuum.c:7966-8001). 이 함수는 debug 빌드에서 "데이터 없음"을 assert하므로 R4도 같이 지킨다.
- L6. 페이지 LSA 정책은 하나만 고른다.
  - (A) copydb 동등: 모든 perm 페이지의 io off 0 LSA와 워터마크(io 끝-8)를 NULL로 둔다(`fileio_reset_page_lsa`, D: file_io.h:211-218, file_io.c:2843). `fpageid = 0`.
  - (B) 페이지 무수정: `F = 출발 append_lsa.pageid + 1`, `fpageid = nxarv_pageid = F`, `append_lsa = chkpt_lsa = (F,0)`, 물리 1 `logical_pageid = F`. 검사: 모든 페이지 LSA < (F,0)이어야 한다. WAL 때문에 정상 종료 DB에서는 `page_lsa ≤ 출발 append_lsa`가 성립하므로 스캔 없이 보장된다고 보지만 [VERIFY]. 이 조건이 깨지면 flush 때 `logpb_flush_log_for_wal`의 assert에 걸린다(D: log_page_buffer.c:4239-4266).
- L7. 도착 디렉터리에 출발 `_dwb`, `_lgar*`, `_lgar_t`, `_bkvinf`, 백업 볼륨이 없어야 한다.

**볼륨 (V)**
- V1. 볼륨 헤더는 L4의 두 필드만 바꾼다. 경로가 바뀌면 `vol_fullname`과 이전 볼륨의 `next_vol_fullname` 문자열을 바꾸고, 세 오프셋을 다시 계산한다(`disk_vhdr_set_*` D: disk_manager.c:5328-5355; 합계 ≤ DB_PAGESIZE).
- V2. 볼륨 헤더 magic/`sect_npgs == 64`/`stab_first_page == 1`/`sys_lastpage == stab_first_page+stab_npages-1`이 아니면 거부한다.

**섹터 테이블과 파일 해제 (F)**: 카탈로그 파일이나 옛 인덱스 파일을 버릴 때
- F1. 헤더 페이지(VPID = `{fileid, volid}`)를 읽는다. partial 표(헤더 안 `offset_to_partial_ftab` → extdata, 이어서 `vpid_next` 사슬 페이지의 off 0 extdata)와 full 표를 모두 걸어 VSID 집합을 모은다. 검사: 개수 == `n_sector_total`, partial 항목 수 == `n_sector_partial`, full == `n_sector_full`.
- F2. 각 VSID에 대해 §2.3 위치의 STAB 비트가 1인지 검사한 뒤 0으로 만든다. 한 섹터를 두 파일이 쓰는 경우는 없으므로, 이미 0이면 손상으로 보고 중단한다.
- F3. 트래커 사슬에서 `{volid, fileid}` 항목을 지우고 뒤 항목을 당기며 `n_items`를 1 줄인다. 검사: 정확히 1개 존재. 항목 `type` == 헤더 off 140 `type`.
- F4. 그 파일의 모든 페이지(헤더, 표 페이지, 사용자 페이지)의 `ptype`(io off 14) = 0, `pflag`(15) = 0. 엔진의 dealloc 의미와 같다(`pgbuf_dealloc_page` D: page_buffer.c:15126-15179). L6(A)에서는 LSA도 NULL로 둔다.
- F5. `BOOT_DB_PARM`이나 다른 메타데이터에 남아 있는 VFID/HFID/BTID 참조를 지운다. 이 부분은 카탈로그 재생성 티켓 소관이다.

**파일 할당 (N)**: 새 카탈로그 heap, representation, classname ehash 등
- N1. 섹터 선택: 볼륨의 STAB에서 0인 비트를 고른다(`sectid > SECTOR_FROM_PAGEID(sys_lastpage)`이고 `< nsect_total`). 비트를 1로 둔다.
- N2. `fileid = SECTOR_FIRST_PAGEID(첫 섹터) = sectid × 64`. 헤더 페이지는 develop 레이아웃(§2.4, 200 B)으로 쓴다. 표는 §2.4 배치를 따르고, 헤더 페이지의 partial 비트를 켠다. 카운터는 `file_create`(D: file_manager.c:3480-3810) 공식대로: `n_page_total = n_sector_total×64`, `n_page_ftab = 표 페이지 수`, `n_page_user = 할당 페이지 수`, `n_page_free = total - user - ftab`; `n_sector_empty`는 비트맵이 0인 partial 섹터 수, 꽉 찬 섹터는 full 표로 옮긴다. 헤더 페이지 `ptype = 1 (PAGE_FTAB)`.
- N3. 검사(엔진 debug의 `file_header_sanity_check`와 같은 식, D: file_manager.c:912-1025): `free+user+ftab == total`, `partial+full == sector_total`, `empty ≤ partial`, `free == 0`이면 `full == total`.
- N4. 트래커에 `{fileid, volid, type, metadata=0}`을 정렬 위치에 넣는다. 페이지가 차면 트래커 파일에서 페이지를 할당해 `vpid_next`로 잇는다. 그러면 트래커 파일 헤더의 카운터와 partial 비트도 함께 바뀐다.
- N5. 새로 쓴 모든 페이지에 `prv.pageid/volid/ptype`을 채우고 LSA는 L6 정책을 따른다. 워터마크 = `prv.lsa`.

**vacuum과 dropped files (R)**
- R4. vacuum data 첫 페이지(`descriptor.vacuum_data.vpid_first`): `next_page = NULL VPID(-1,-1)`, `index_unvacuumed = 0`, `index_free = 0`, `data[0].blockid = -1`. dropped files 첫 페이지(sticky): `next_page = NULL`, `n_dropped_files = 0`.

**11.4 파일 헤더 (H)**
- H1. 복사한 11.4 파일 헤더는 고치지 않는다. 검사: `offset_to_partial_ftab ≥ 200`, `full`(perm이면) ≥ 200, `< DB_PAGESIZE`. 11.4가 만든 값은 216 이상이다.

## Open questions

1. [VERIFY] L6(B): release 빌드에서 `fpageid > 0`인 빈 로그로 부팅하는 경우. vacuum 블록 계산(`logpb_last_complete_blockid` D: log_page_buffer.c:12170-12184는 `prev_lsa`가 NULL이면 -1)과 checkpoint, archive 경로가 실제로 통과하는지 smoke가 필요하다. 근거로 삼은 `PRM_ID_FIRST_LOG_PAGEID`는 `!NDEBUG`에서만 쓰인다(D: log_page_buffer.c:1381-1385, 2547-2552).
2. [VERIFY] sparse `_lgat`(물리 0, 1만 쓴 파일)로 첫 부팅. copydb가 같은 모양을 만들므로 통과를 예상하지만 smoke로 확인하지 않았다.
3. 결정 필요: L6 (A)와 (B) 중 무엇을 쓸까. (A)는 모든 페이지에 쓰므로 clone 모드에서 reflink 이득이 사라진다. (B)는 첫 수정 전까지 페이지를 공유할 수 있다.
4. vacuum data 파일에 페이지가 여럿 남아 있을 때 R4가 첫 페이지 사슬만 끊으면 나머지 페이지는 할당된 채 고아가 된다. 그 페이지까지 partial 비트맵에서 해제할지(파일 내부 dealloc 규칙)는 정하지 않았다.
5. 인덱스 재빌드를 도착 엔진(loaddb)이 한다면, 옛 B-tree 파일을 Rust가 F1–F4로 미리 해제할지, 아니면 엔진의 DROP/CREATE에 맡길지. 클래스 객체 안 BTID 처리 방식에 달렸다.
6. 범위 밖이지만 발견한 사실: slotted page 헤더 비트필드에서 `need_update_best_hint` 비트가 삭제되었다(`e84a7f6dc` [CBRD-26176] #7353, D: slotted_page.h:76-81). 11.4 heap 페이지에 남은 이 비트를 develop은 `reserved_bits`로 본다. heap 페이지 담당 티켓에서 확인할 것.
7. `databases.txt` 등록(`LOG_DBTXT_VOLID`)은 이 문서 범위 밖이다.

## Sources

- develop `5b1867174`: src/transaction/boot_sr.c (122-142, 1024-1131, 2380-2440, 2604-2614, 4916-5195, 6200-6230); src/transaction/log_manager.c (683-732, 837-992, 1108-1585, 8924-9010); src/transaction/log_page_buffer.c (455-522, 1297-1459, 2532-2608, 4239-4266, 4593-4622, 4761-4913, 5026-5059, 7148-7190, 9971-10464, 12155-12184); src/transaction/log_storage.hpp (62-224); src/transaction/log_lsa.hpp (37-119); src/transaction/log_record.hpp (35-153); src/transaction/log_volids.hpp; src/storage/disk_manager.c (74-231, 512-814, 852-1136, 2567-2618, 3166-3279, 3817-3834, 4930-5013, 5328-5525); src/storage/file_manager.c (88-218, 475-499, 912-1025, 1468-1499, 2772-2812, 2983-2997, 3440-3830, 4109-4339, 9927-10242); src/storage/file_manager.h (37-168); src/storage/file_io.h (62-218); src/storage/file_io.c (2309-2466, 2786-2960, 11714-11725, 11970-11977); src/storage/storage_common.h (100-117, 149-166, 342, 414-422); src/storage/storage_common.c (44-83); src/query/vacuum.c (105-214, 581-611, 4195-4596, 7966-8011); src/storage/double_write_buffer.cpp (3200-3240); src/base/release_string.c (105, 293-329); src/base/CRC.h (1567-1571); src/base/bit.c (574-602); src/object/system_metadata_version.h; CMakeLists.txt (176-181).
- release/11.4 `46212adcd`: src/transaction/log_storage.hpp (113-195); src/storage/file_manager.c (91-165); src/storage/file_manager.h (38-54); src/transaction/boot_sr.c (113-132); src/base/release_string.c (105); src/transaction/log_page_buffer.c (1435-1437); src/storage/storage_common.h (151-166).
- 커밋/PR: `ecb0915e4` CBRD-26049 (#6706, disk 11.5f); `9ee8bac8b` CBRD-26459 (#7773, sysmeta_version); `b319ce1ab` CBRD-27320 (#7875, LOG_LSA_ATOMIC 레이아웃 보존); `1ea077d85` CBRD-27308 (#7792, FILE_HEADER 216→200); `69c3094f1`/`6186f8cca` CBRD-27179 (#7838/#7790, cdc_arv_num_to_keep, 두 줄기 모두 있음); `1a89b445b` CBRD-22174 (#1148, boot_after_copydb); `e84a7f6dc` CBRD-26176 (#7353, slotted page 비트).
- 계산값: 오프셋은 위 구조체를 옮겨 적은 C 프로그램을 gcc x86-64로 돌려 `offsetof`로 얻었다. float 바이트는 Python `struct.pack('<f')`로 얻었다. 16K 파생값(16344, 130752, 8048 등)은 산술로 구했다.
