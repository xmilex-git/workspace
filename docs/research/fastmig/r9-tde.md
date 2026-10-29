# R9 — 11.0 TDE 도입(CBRD-23789)의 페이지 변경과 TDE 암호화 출발 볼륨 (#510, map #472)

기준: develop = 워크트리 `5b1867174` (R1과 같은 기준. `origin/develop@682b080b2`와 비교해 tde.c·tde.h·file_io.h·log_storage.hpp에 diff 없음), 릴리스 선 `origin/release/10.2@416bb667c`, `11.0@44ea22369`, `11.1@e0e4f7a84`, `11.2@baf1d297d`, `11.3@8acbed10e`, `11.4@46212adcd`.
gdb `ptype /o` 교차 확인은 release install의 `lib/libcubrid.so`로 했다: CUBRID-10.2.18.9024, 11.0.16.0419, 11.2.9.0866, 11.4.6.1963 (증거: `.git_ignored_dir/scratch/map472-pairs/510/gdb-*.txt`, `s-*.txt`). 계산으로 얻은 값에는 "(계산)"을 붙였다. 16K 페이지 기준 `DB_PAGESIZE`=16344 (R1).

## 1. 결론

1. TDE 구현은 CBRD-23608 `0cf60dd26` (2020-11-19, 92파일 +5909)이다. CBRD-23789 `37720d8ed` (#2495)는 그 직후 `disk_compatibility_level`을 10.15f→11.0f로 올린 **한 줄 커밋**이다 (release_string.c:102@10.2 → :101@11.0).
2. `FILEIO_PAGE_RESERVED`(32B)는 크기와 오프셋이 그대로다. 이름만 바뀌었다: +15 `pflag_reserve_1`→`pflag`, +24 `p_reserve_3`→`tde_nonce` (file_io.h:182,185@10.2 → file_io.h:175@develop; gdb 10.2.18 vs 11.0.16 확인). 10.2는 두 필드를 항상 0으로 쓴다 (file_io.c:11612-11615, page_buffer.c:4629-4632, 4812-4815, 10230-10233 @10.2).
3. 11.0+/develop은 `pflag & 0x3 == 0`인 페이지를 평문으로 읽고 `tde_nonce`를 보지 않는다 (page_buffer.c:8499-8510 @develop). 그러므로 **10.2 페이지는 TDE 관점에서 바이트 그대로 읽힌다.** 10.2→develop에서 TDE 때문에 전 페이지 transform을 할 필요는 없다.
4. 10.2↔11.0 사이에 TDE가 바꾼 디스크 구조는 셋이다. (a) `BOOT_DB_PARM` 124B→136B: +124에 `tde_keyinfo_hfid` 추가 (gdb). (b) 클래스 객체 고정부에 `tde_algorithm` int 추가, `_db_class.tde_algorithm` 칼럼 추가 (transform_cl.c, catalog_class.c, `0cf60dd26`). (c) `LOG_HDRPAGE` +10 `dummy1`→`flags` (log_storage.hpp). 볼륨 헤더, `FILE_HEADER`, `HEAP_HDR_STATS`, `SPAGE_HEADER`, `BTREE_ROOT_HEADER`, `LOG_HEADER`는 gdb로 10.2.18과 11.0.16에서 **같다**.
5. 10.2 출발에는 TDE 키 자산이 없다(`_keys` 파일, keyinfo heap). develop 도착은 createdb처럼 둘을 **새로 만들어야** 한다(boot_sr.c:5033, 5159 @develop). 없으면 release는 `ER_TDE_CIPHER_LOAD_FAIL`만 남기고 부팅하지만 TDE 테이블을 만들 수 없다 (boot_sr.c:2330-2335). optdebug에서는 NULL HFID로 `tde_get_keyinfo`의 assert에 걸릴 수 있다 (tde.c:589).
6. 암호화 범위: TDE 클래스 파일(heap, heap overflow, B-tree, B-tree overflow key)의 **사용자 페이지**, TDE 클래스를 다루는 temp 파일(list·sort), 사용자 데이터를 담은 로그 레코드가 있는 로그 페이지다. 파일 헤더 페이지와 파일 테이블 페이지는 평문이다 (file_manager.c:7328-7332). `FILEIO_PAGE_RESERVED` 32B와 워터마크 8B는 항상 평문이고, `[32, IO_PAGESIZE−8)` 구간만 암호문이다 (tde.c:994-1002).
7. 알고리즘은 페이지마다 AES-256-CTR(`pflag` 0x1) 또는 ARIA-256-CTR(0x2)이다. IV 16B는 영구 페이지에서 `tde_nonce`(8B, 쓸 때의 page LSA) ‖ 0×8, 로그 페이지에서 `logical_pageid`(8B) ‖ 0×8이다. 복호화는 저장된 `tde_nonce`를 쓰고 LSA는 다시 읽지 않는다 (tde.c:990, 999, 1048). 인증 태그(MAC)는 없다.
8. 키 계층: `<db>_keys` = 매직 25B("CUBRID/Keys") + `TDE_MK_FILE_ITEM`{`created_time` i64, `master_key` 32B} 40B × 최대 128개. **마스터 키는 평문으로 저장된다.** keyinfo heap의 레코드(4B 더미 + `TDE_KEYINFO` 152B)가 `mk_index`, SHA-256(mk), 그리고 AES-256-CTR(mk)로 암호화한 data key 3개(perm/temp/log)를 갖는다. data key의 IV는 16B를 0x00/0x01/0x02로 채운 고정값이다 (tde.c:932-945).
9. TDE 형식은 11.0부터 develop까지 **바뀌지 않았다**. tde.h 상수와 구조체가 같고(gdb 11.0.16 = 11.4.6), tde.c의 차이는 11.2 로그·에러 정리(CBRD-24091 #3151, CBRD-24102 #3168), 11.4 메모리 래퍼 include(CBRD-25068 #5240), develop의 OpenSSL 3 EVP 이식(CBRD-27091 #7905)·컨텍스트 풀(CBRD-27449 #7986)·keys 파일 재사용 허용(CBRD-26176 #7353)뿐이다. **11.0~11.4 TDE 출발 → develop은 키 자산을 그대로 옮기면(`_keys` 복사 + keyinfo heap 유지) 암호문 페이지도 as-is로 읽힌다.**
10. 판정: TDE는 어느 쌍에서도 전 페이지 transform을 요구하지 않는다. TDE 출발을 지원하려면 페이지 단위 AES/ARIA-256-CTR 복호화·재암호화 패스가 필요하다. 대상은 patch·transform 대상 페이지, 재빌드한 B-tree 페이지, 검증기와 인덱스 빌더가 읽는 힙 페이지다. Rust에 필요한 프리미티브는 AES-256, ARIA-256, CTR(128비트 BE 카운터), SHA-256이고, 키를 새로 만들 때만 CSPRNG가 더 필요하다. 지금 도구는 TDE 파일을 거부한다 (`migration_plan.rs:227-238` @fastmig `fec6138`).

## 2. 항목별 표

### 2.1 커밋과 디스크 호환 레벨

| 영역 | 버전별 값 | 커밋 / PR |
|---|---|---|
| TDE 구현 | 10.2: 없음 / 11.0+: 있음 | CBRD-23608 `0cf60dd26` (2020-11-19). 같은 기능의 후속: `fff26f6ac` #2546, `625f58c48` #2551 (Windows 마스터 키 변경) |
| `disk_compatibility_level` | 10.2 10.15f / 11.0·11.1 11.0f / 11.2·11.3 11.2f / 11.4 11.4f / develop 11.5f (release_string.c:101~105) | 11.0 상향 CBRD-23789 `37720d8ed` #2495 (2020-11-19, 1줄) |
| `disk_compatibility_rules[]` | 11.0에서도 빈 테이블 (release_string.c @11.0) | 엔진에 10.2→11.0 변환 경로 없음 |

### 2.2 `FILEIO_PAGE_RESERVED` (모든 페이지, 페이지 오프셋) — 10.2 vs 11.0+

gdb `ptype /o` 10.2.18 / 11.0.16 / 11.4.6. 11.0과 11.4는 출력이 같다.

| off | size | 10.2 | 11.0 ~ develop | 비고 |
|---|---|---|---|---|
| 0 | 8 | `lsa` | `lsa` | 평문 |
| 8 | 4 | `pageid` | 같음 | |
| 12 | 2 | `volid` | 같음 | |
| 14 | 1 | `ptype` | 같음 | |
| 15 | 1 | `pflag_reserve_1` (항상 0) | `pflag`: 0x1 AES, 0x2 ARIA, mask 0x3 (file_io.h:63-66 @develop) | 10.2 값 0 = 평문 |
| 16 | 4 | `p_reserve_1` | 같음 (0) | |
| 20 | 4 | `p_reserve_2` | 같음 (0) | |
| 24 | 8 | `p_reserve_3` (항상 0) | `tde_nonce`: 영구 페이지는 page LSA, temp 페이지는 원자 카운터 (file_io.h:175) | 평문 |
| 32 | `DB_PAGESIZE` | 사용자 영역 | TDE면 암호문 | |
| IO−8 | 8 | 워터마크 `prv2.lsa` | 같음, 평문 (tde.c:996-997) | `fileio_is_page_sane`은 암호문 상태에서도 성립 |

10.2가 0을 쓰는 곳: file_io.c:11612-11615, page_buffer.c:4629-4632, 4812-4815, 10230-10233 @10.2. DWB도 0을 assert한다 (double_write_buffer.c:2057-2059 @10.2). TDE 커밋이 이 assert를 지웠다 (`0cf60dd26` double_write_buffer.c).

### 2.3 그 밖의 구조체 — 10.2 vs 11.0 (gdb)

| 구조체 | 10.2.18 | 11.0.16 | 11.4.6 / develop | 커밋 |
|---|---|---|---|---|
| `DISK_VOLUME_HEADER` | 128B | 128B (같음) | 136B: +80 `vol_creation` 삽입, `chkpt_lsa` 이후가 8B 밀림 | CBRD-25365 `44c022c31` #5719 (11.3→11.4, TDE 아님. R8 소관) |
| `BOOT_DB_PARM` | 124B, `dropped_files_vfid`@116에서 끝 | 136B, +124 `tde_keyinfo_hfid` (HFID 12B) | 136B (R5: 11.4=develop) | `0cf60dd26` |
| `LOG_HDRPAGE` | 16B, +10 `short dummy1` | 16B, +10 `short flags` (0x1 AES, 0x2 ARIA; log_storage.hpp:37-49) | 같음 | `0cf60dd26` |
| `LOG_HEADER` | 376B | 376B (구조체 텍스트 diff 0) | R1·R5 참조 | — |
| `FILE_HEADER` | 216B | 216B (같음). `file_flags` 0x4 AES, 0x8 ARIA는 11.0에서 새로 쓰는 비트 | 200B (develop, R1) | `0cf60dd26` |
| `HEAP_HDR_STATS`, `SPAGE_HEADER`, `BTREE_ROOT_HEADER` | 296 / 32 / 88B | 같음 | R1 참조 | — |
| 클래스 객체 (root heap 레코드) | `tde_algorithm` 없음 | `put_class_attributes`가 `or_put_int(tde_algorithm)` 추가 (transform_cl.c:3696 @11.0) | R3: 고정부 +164 | `0cf60dd26` |
| `_db_class` | `tde_algorithm` 칼럼 없음 | `tde_algorithm int` (transform.c:293 @11.0, catalog_class.c `CATCLS_INDEX_KEY` 10→11) | R4 | `0cf60dd26` |
| `MVCC`/OR 값 인코딩 | — | TDE 커밋은 바꾸지 않음 | — | — |

### 2.4 암호화 범위 (develop, 11.0과 같음)

| 대상 | 암호화 | 근거 |
|---|---|---|
| TDE 클래스 heap / heap overflow / B-tree / B-tree overflow key 파일의 사용자 페이지 | 예. 힙 헤더 페이지(slot 0 `HEAP_HDR_STATS`)와 B-tree root 헤더 페이지도 사용자 페이지이므로 포함 | `file_apply_tde_algorithm` 호출: heap_file.c:4977, 6120, btree.c:2062, 37642, file_manager.c:12474-12540 (`xfile_apply_tde_to_class_files`) |
| 그 파일의 파일 헤더·파일 테이블 페이지 | 아니요 | file_manager.c:7328-7332 ("skip table pages"). 헤더의 `file_flags` 0x4/0x8만 표시 (file_manager.c:152-161, 5884-5905) |
| 새로 할당한 사용자 페이지 | 파일 헤더의 알고리즘을 `pflag`에 설정 | file_manager.c:5491-5506 |
| 해제한 페이지 | `pflag` 비트를 0으로 지움 | page_buffer.c:15157-15167 |
| temp 파일 (list, sort, btree sort) | TDE 클래스를 다룰 때 예, key = `temp_key`, nonce = 프로세스 카운터 | query_manager.c:2928, 3205, external_sort.c:2118, 4354, btree_sort.c:1607, 3596; tde.c:981-984 |
| 로그 페이지 | `LOG_MAY_CONTAIN_USER_DATA(rcvindex)` 레코드가 TDE 파일에 대한 것이면 그 페이지 전체. 알고리즘은 `tde_default_algorithm` 파라미터 | tde.h:107-137, log_page_buffer.c:2727-2731, 4303-4309; 암호 구간은 `LOG_HDRPAGE` 16B 뒤 (tde.h:45-46) |
| 로그 헤더 페이지 (`LOGPB_HEADER_PAGE_ID`) | 레코드를 담지 않으므로 해당 없음 | log_storage.hpp:52 주석 |
| DWB | 암호화한 뒤의 이미지를 담는다 | page_buffer.c:10748-10760 (암호화 후 `dwb_set_data_on_next_slot`) |
| keyinfo heap, boot parm heap, root heap, 카탈로그 | 평문 (시스템 파일, tde_algo NONE) | tde.c:111-226 |
| 백업 | 페이지를 그대로 담는다. `--separate-keys`면 `_keys`를 따로 둔다 | `logpb_backup(..., separate_keys)` (`0cf60dd26` log_impl.h) |

### 2.5 암호 파라미터

| 항목 | 값 | 근거 |
|---|---|---|
| 데이터 페이지 | AES-256-CTR 또는 ARIA-256-CTR, key = `perm_key`(영구) / `temp_key`(temp), IV = `tde_nonce` LE 8B ‖ 0×8 | tde.c:965-1055; crypt_opfunc.c:293-296 (`EVP_aes_256_ctr`, `EVP_aria_256_ctr`); 11.0은 tde.c:1079-1082에서 직접 호출 |
| 영구 페이지 nonce 값 | 쓸 때의 `prv.lsa` 8B (`pageid:48 | offset:16` 비트필드, log_lsa.hpp:37-41) | tde.c:988-990 |
| 로그 페이지 | 같은 알고리즘, key = `log_key`, IV = `logical_pageid` 8B ‖ 0×8, 구간 `[16, LOG_PAGESIZE)` | tde.c:1066-1115, tde.h:45-46 |
| data key 암호화 | 항상 AES-256-CTR (`TDE_DK_ALGORITHM`), key = master key, IV = 16B를 perm 0x00 / temp 0x01 / log 0x02로 채움 | tde.h:40, tde.c:893-945 |
| 마스터 키 검증 | SHA-256(mk) == `keyinfo.mk_hash`, 그리고 keys 파일 항목의 `created_time` == `keyinfo.created_time` | tde.c:717-750, 794-852 |
| 키 길이 | master key·data key 모두 32B | tde.h:54-55 |
| CTR 카운터 | 16344B = 1021.5블록이므로 하위 8B 카운터가 넘쳐 nonce 8B로 올라가는 일이 없다 (계산) | — |

### 2.6 키 파일 `<db>_keys`와 keyinfo 레코드

| 위치 | 크기 | 내용 | 근거 |
|---|---|---|---|
| keys 파일 0 | 25 | `CUBRID_MAGIC_KEYS` "CUBRID/Keys" + 0 채움 (`CUBRID_MAGIC_MAX_LENGTH`=25) | storage_common.h:414, 422; tde.c:354-355 |
| keys 파일 25 + 40·i | 40 | `TDE_MK_FILE_ITEM` i: `created_time` time_t(8) @0, `master_key[32]` @8. `created_time == -1`이면 빈 자리 | tde.h:92-96, tde.c:1556-1630 (gdb 40B) |
| 항목 수 | ≤ 128 | `TDE_MK_FILE_ITEM_COUNT_MAX` | tde.h:65 |
| 위치·권한 | 기본 `<db_full_name>_keys` (볼륨 디렉터리), `tde_keys_file_path` 파라미터로 바꿀 수 있음. 0600으로 만든다 | file_io.c `fileio_make_keys_name` sprintf("%s%s"), tde.c:512-527, tde.c:346 |
| 매직 검사 | `memcmp(..., sizeof(CUBRID_MAGIC_MAX_LENGTH))` = 앞 4B만 비교 (엔진 결함, 11.0부터 그대로) | tde.c:394 @develop, :374 @11.0 |
| keyinfo HFID | `BOOT_DB_PARM.tde_keyinfo_hfid` @124 | boot_sr.c:141 @develop |
| keyinfo 레코드 | 156B (계산) = `int` 더미 0 (vacuum 회피 HACK) + `TDE_KEYINFO` 152B, REC_HOME, heap의 첫 레코드 | tde.c:203-222, 581-607 |
| `TDE_KEYINFO` | `mk_index`@0 i32, (hole 4), `created_time`@8, `set_time`@16, `mk_hash[32]`@24, `dk_perm[32]`@56, `dk_temp[32]`@88, `dk_log[32]`@120 | gdb 11.0.16 = 11.4.6 |
| 생성 시점 | 모든 11.0+ createdb가 keys 파일(마스터 키 1개)과 keyinfo 레코드를 만든다. TDE 테이블이 없는 DB도 있다 | boot_sr.c:5033 (heap 생성), 5159 (`tde_initialize`) @develop |
| 마스터 키 교체 | `tde_change_mk`가 keyinfo의 `mk_index`/hash/data key 암호문을 바꾼다. data key 평문은 그대로다 | tde.c:673-710 |

### 2.7 11.0 ~ develop TDE 변경

| 구간 | tde.c / tde.h diff | 형식 영향 | 커밋 / PR |
|---|---|---|---|
| 11.0→11.1 | 없음 | 없음 | — |
| 11.1→11.2 | `tde_is_loaded()`, `tde_er_log` 매크로 | 없음 | CBRD-24091 `b5d1e63bd` #3151, CBRD-24102 `5856b5a23` #3168 |
| 11.2→11.3 | 없음 | 없음 | — |
| 11.3→11.4 | `memory_wrapper.hpp` include | 없음 | CBRD-25068 `3d16a34c4` #5240 |
| 11.4→develop | SHA256_*→EVP digest, `EVP_*` 이식, 컨텍스트 풀(`reuse_ctx`), 기존 keys 파일이 있으면 재사용 | 없음 (상수·오프셋·IV·키 계층 같음) | CBRD-27091 `9aabaa226` #7905, CBRD-27449 `60f4da8e8` #7986, CBRD-26176 `e84a7f6dc` #7353 |

## 3. 쌍별 판정 (TDE 관점, develop 도착)

| 출발 | 평문 DB | TDE 테이블이 있는 DB |
|---|---|---|
| 10.2 | 페이지 예약 영역은 as-is(clone/copy). TDE가 만든 차이는 transform 3개다. ① boot parm 레코드를 124B→136B로 다시 쓴다. ② keyinfo heap과 그 레코드를 새로 만든다. ③ `<db>_keys`를 새로 만든다: 마스터 키 1개, 새 data key 3개, createdb와 같은 절차. 클래스 객체와 `_db_class`의 `tde_algorithm`=0은 카탈로그 재생성에 들어간다. 볼륨 헤더 8B 이동(11.4 변경)은 R8 소관이다. | 해당 없음 (10.2에는 TDE가 없다) |
| 11.0 / 11.1 / 11.2 / 11.3 | TDE 차이 없음. `_keys` 복사, keyinfo heap 유지 (11.4 경로와 같다). | 형식이 develop과 같다. 키 자산을 그대로 옮기면 손대지 않는 암호문 페이지는 clone/copy as-is로 된다. 복호화가 필요한 곳은 아래 §4. |
| 11.4 | 같음 (R1/R5 결론 유지) | 같음. 지금 구현은 거부한다 (`migration_plan.rs:227-238`). |

결론: **TDE 때문에 바뀌는 페이지 처리 등급은 없다.** 다만 TDE 출발에서 patch·transform 대상이 되는 페이지(힙 헤더·bestspace·vacuum 잔여 페이지, 재빌드 B-tree)는 "복호화 → 기존 처리 → 재암호화"를 거쳐야 한다.

## 4. 복호화 패스에 필요한 것 (설계 입력)

입력
- 출발 볼륨, `<db>_keys` (기본 위치는 볼륨 디렉터리. `tde_keys_file_path`로 옮겼을 수 있으므로 `--keys-file` 같은 경로 입력이 필요하다).
- `BOOT_DB_PARM.tde_keyinfo_hfid` → keyinfo heap 첫 레코드 → `TDE_KEYINFO`.

키 적재 (엔진 `tde_cipher_initialize`와 같은 순서)
1. keys 파일 매직 25B를 확인한다 (엔진보다 엄격하게 전체 비교).
2. 항목 `mk_index`를 읽는다: 오프셋 25+40·`mk_index` (계산). `created_time != -1`이고 `== keyinfo.created_time`이어야 한다.
3. SHA-256(mk) == `mk_hash`를 확인한다. 다르면 거부한다. CTR에는 MAC이 없어서 틀린 키도 쓰레기 평문을 조용히 내기 때문이다.
4. `dk_perm`, `dk_temp`, `dk_log`를 AES-256-CTR(mk, IV=0x00/0x01/0x02×16)로 푼다. 오프라인 이주에 실제로 필요한 것은 `perm_key`뿐이다. 로그·temp·DWB는 옮기지 않기 때문이다 (R1 §1-8, R5).

페이지별
- `pflag & 3`: 1 AES, 2 ARIA, 3이면 손상으로 본다 (엔진 assert, page_buffer.c:5101-5102).
- 평문 = CTR_dec(perm_key, IV = page[24..32] ‖ 0×8, page[32 .. IO−8]). 헤더 32B와 워터마크 8B는 그대로 둔다.

출력 모드 (사람이 정할 일, 남은 질문 Q1)
- (A) 키 유지: `_keys`를 복사하고 keyinfo heap을 유지한다. 손대지 않는 페이지는 암호문 그대로 clone/copy한다. 다시 쓰는 페이지는 같은 `perm_key`로 다시 암호화한다. 파일 헤더 플래그, 클래스 `tde_algorithm`, `_db_class.tde_algorithm`은 그대로 둔다.
- (B) 평문화: 모든 암호 페이지를 풀고 `pflag`, `FILE_HEADER.file_flags` 0x4/0x8, 클래스 `tde_algorithm`, `_db_class.tde_algorithm`을 0으로 만든다. 사용자에게 보이는 스키마(`ENCRYPT=`)가 바뀐다.
- (C) 재키잉: 새 마스터 키와 data key를 만들고 암호 파일 전체를 다시 암호화한다. 암호 파일은 전부 transform이 된다.

nonce 주의 (모드 A, C)
- 엔진은 쓰기 때마다 nonce = page LSA를 쓴다. G4(#485)의 새 로그는 출발 append LSA보다 큰 F에서 시작하므로 이주 뒤 엔진의 쓰기가 출발 페이지의 (key, nonce)를 재사용하지 않는다 (계산).
- 도구가 새로 할당하는 페이지(bestspace, 재빌드 B-tree)는 지금 LSA를 NULL로 쓴다 (`ondisk/src/page.rs:126`, P1a #490). 이 페이지들을 nonce=LSA로 암호화하면 모든 페이지가 같은 nonce `0xFFFF_FFFF_FFFF_FFFF`를 쓴다 (`NULL_LSA`={-1,-1}, log_lsa.hpp:115) (계산). CTR 키스트림이 재사용되어 두 페이지의 평문 XOR이 드러난다. 복호화는 저장된 `tde_nonce`만 쓰므로, 도구는 페이지마다 엔진의 LSA 공간과 겹치지 않는 고유 nonce를 넣으면 된다. 예: pageid 필드가 −2 이하인 값을 차례로 쓴다 (제안, 미검증).
- patch한 페이지를 원래 `tde_nonce`로 다시 암호화해도 읽기는 된다. 그러나 출발 사본과 도착 사본을 함께 가진 사람에게 바뀐 바이트의 XOR이 드러난다. 새 nonce를 쓰는 편이 안전하다.

Rust 프리미티브: AES-256 블록(`aes`), ARIA-256 블록(`aria`), CTR 128비트 big-endian 카운터(`ctr::Ctr128BE`, OpenSSL `CRYPTO_ctr128_encrypt`와 같은 증분), SHA-256(`sha2`). 모드 C와 10.2 키 생성에는 CSPRNG(`getrandom`)가 더 필요하다. 모두 순수 Rust 크레이트라 "엔진 바이너리 의존 0" 원칙과 맞는다. 성능: CTR은 페이지 단위로 독립이라 copy 엔진의 `InlineTreatment` 훅(P1e #494)에서 워커 병렬로 돌릴 수 있다.

## 5. 남은 질문

티켓으로 만들 수 있는 질문
- Q1 (grilling) TDE 출발의 출력 모드를 고른다: (A) 키 유지 + 다시 쓰는 페이지만 재암호화, (B) 평문화(스키마의 `ENCRYPT=`가 사라짐), (C) 재키잉. ➡️ 추천: (A). 엔진의 암호 형식이 11.0부터 develop까지 같고, 손대지 않는 페이지는 clone이 그대로 되고, 사용자 스키마가 바뀌지 않는다.
- Q2 (task/prototype) TDE 출발 지원 prototype: 11.4.6 T1 크기 DB에 `ENCRYPT=AES` 테이블과 `ENCRYPT=ARIA` 테이블을 하나씩 만든다. Rust로 keys/keyinfo를 적재하고 페이지를 복호화해서, 엔진이 평문으로 내는 값(`unloaddb`)과 같은지 확인한다. 같은 페이지를 다시 암호화했을 때 develop optdebug CS가 부팅·DML·재부팅에서 assert 0인지도 본다. 전제: Q1.
- Q3 (research) 재빌드 B-tree와 bestspace 페이지의 nonce 규칙: 엔진이 NULL LSA인 영구 TDE 페이지를 쓰는 경로가 있는가 (예: `loaddb --no-logging-index`, `pgbuf_copy_from_area`)? 엔진 스스로 nonce를 재사용한다면, 도구의 고유 nonce 규칙도 그 수준에 맞추면 되는지 판단한다.
- Q4 (task) 10.2 출발의 TDE 자산 생성: boot parm 136B 재기록 + keyinfo heap 생성 + `_keys` 생성을 Rust로 할지, develop의 SA 유틸리티로 할지 정한다 (예: 빈 keyinfo만 만들고 엔진에 맡길 수 있는가). keys 파일이 없을 때 develop release/optdebug의 부팅 동작을 실측한다 (boot_sr.c:2330-2335 경로). 위치는 R8·T4(#512) 뒤.

아직 흐릿한 것 (fog)
- `tde_keys_file_path`로 키 파일을 DB 밖에 두는 운영 환경에서 도착 키 파일을 어디에 둘지. 도구가 cubrid.conf를 읽을지는 G1 CLI 계약과 함께 다룬다.
- HA·복제 로그의 TDE(`UNSTABLE_TDE_FOR_REPLICATION_LOG`, 비활성)는 오프라인 전용 범위 밖으로 보이지만, 지도의 Out of scope에 적지 않았다.
- 10.2 `LOG_HDRPAGE.dummy1`이 늘 0이었는지는 확인하지 않았다. 로그를 새로 쓰므로 판정에는 영향이 없다.
- 백업(`backupdb --separate-keys`)에서 출발하는 이주는 지도에서 다루지 않았다.

## 6. 근거 명령

- `git show 0cf60dd26 -- src/storage/file_io.h src/transaction/log_storage.hpp src/transaction/log_volids.hpp src/storage/double_write_buffer.c src/object/transform_cl.c src/storage/catalog_class.c`
- `git diff origin/release/10.2 origin/release/11.0 -- src/storage/file_io.h`; 구조체 추출 diff (`vh/fh/bp/lhp-*.txt`).
- `git diff --stat origin/release/A origin/release/B -- src/storage/tde.c src/storage/tde.h` (11.0→11.1→…→develop).
- gdb `ptype /o`: `fileio_page_reserved`, `boot_dbparm`, `log_hdrpage`, `tde_keyinfo`, `tde_mk_file_item`, `disk_volume_header`, `heap_hdr_stats`, `file_header`, `spage_header`, `btree_root_header`, `log_header` — 10.2.18 / 11.0.16 / 11.2.9 / 11.4.6 release `libcubrid.so`.
- code-index `callers file_apply_tde_algorithm` @develop: 호출 14곳, 함수 11개.
