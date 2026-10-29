# R6 인덱스 빌드 경로 포팅 범위 (#478, map #472)

기준: develop `5b1867174` (이하 `D:`), release/11.4 `46212adcd` (이하 `11.4:`), PR #8209 head `fec3f773a` (이하 `R:`, 미머지).
`file:line` 은 표기한 커밋의 파일이다. 파일 없이 `:NNNN` 만 쓴 인용은 같은 칸에 앞서 나온 파일, 없으면 `D:src/storage/btree_load.c` 이다.
"계산" 이라고 쓴 값은 구조체·매크로에서 x86-64 GCC 배치 규칙으로 유도한 값이고 디스크에서 직접 읽은 값이 아니다.

## 1. 요약 답

1. no-logging 병렬 빌드(#7504, `1aa79a03b`)는 **힙 섹터 병렬 스캔 → 키 추출(+필터/함수 평가) → 워커별 run 정렬·flush → splitter 로 키 구간 shard 분할 → shard 마다 k-way merge 하며 리프·오버플로 페이지 직접 생성 → 이음매(prev/next) 연결 → 단일 스레드 비리프 생성 → sticky 루트에 복사** 순서다. 11.4 에는 이 경로가 없다(`1aa79a03b` 는 11.4 의 조상이 아님).
2. #8209 는 이 중 "run 정렬" 하나만 MSD radix 로 바꾼다. 정렬 결과(키 오름차순, 같은 키는 OID 오름차순)와 run·페이지 형식은 그대로다(PR 본문). Rust 는 **코드가 아니라 순서**를 옮기면 된다.
3. Rust 가 써야 할 B-tree 형식: 슬롯 페이지(PAGE_BTREE), slot 0 = 노드 헤더(32B, host order) 또는 루트 헤더(고정 88B + packed key domain), slot 1.. = 레코드(big-endian 필드). 리프 레코드 = 첫 OID(플래그 비트 내장) + [class OID] + [MVCCID] + 키 + align4 + 추가 OID들 + [오버플로 VPID 8B].
4. 11.4 → develop 차이는 둘뿐이다: (a) 비유니크 인덱스의 오버플로 OID 체인이 16B 헤더 + OID 디렉터리 형식(CBRD-24094, #7447), (b) 루트 헤더 off 68 의 `rev_level:16|dedup_idx:16` 비트필드가 `int rev_level` 로(CBRD-27324, #8104, 바이트 위치 동일). 리프/비리프 레코드, 플래그 비트, 오버플로 키 파일, MIDXKEY 헤더는 같다. 키 원소 인코딩(CHAR/NUMERIC)과 packed domain 은 R2 범위로 넘긴다.
5. 오프라인·patch 이후(전 행 all-visible) 입력이면 MVCCID 는 하나도 기록되지 않는다. 유니크 키 중복이 나오면 원본 결함이다.
6. PK/unique: 유니크 형식(OID 고정 크기 32B, 레거시 8B 오버플로 헤더) + 루트 헤더 통계 3개. 일반/FK/역인덱스: 비유니크 형식(24B, 디렉터리 체인), 통계 -1. FK 는 빌드 뒤 PK 대조(`btree_load_check_fk`).
7. 함수·필터 인덱스는 XASL 직렬화 식(expr/pred stream)을 행마다 평가해야 하므로 "엔진 의존 0" 과 정면으로 충돌한다(열린 질문 Q1).
8. 파티션: 모든 인덱스가 파티션마다 로컬(n_classes=1)이다. 유니크/PK 는 파티션 키를 반드시 포함한다(ER -1169). 병렬 빌드는 n_classes==1 일 때만 한다.
9. 기준선(#433, develop `8f57aa0d7` release, 1천만 행·varchar 1.2GB): CREATE INDEX 15.1s / loaddb `--no-logging-index` 10.4s / ONLINE PARALLEL 16 96.3s (DWB 켬), DWB 끔이면 13.7 / 5.9 / 58.8s.
10. Rust 이식 대상은 형식·순서·채움 규칙(§3)이고, 페이지 할당 provider·sysop·WAL·DWB 같은 동시성/복구 장치는 오프라인 도구에 필요 없다.

## 2. 단계별 구성 (develop no-logging 병렬 경로 + #8209)

| 단계 | 엔진 위치 | Rust 가 가져올 규칙 |
|---|---|---|
| 0. 진입 | loaddb `-i ... --no-logging-index` → `btree_set_no_logging_index` `D:src/loaddb/load_db.c:844`; 서버는 loaddb 클라이언트만 허용 `D:src/communication/network_interface_sr.cpp:4742-4745`; `xbtree_load_index` `D:src/storage/btree_load.c:1380` | 인덱스 하나 = 호출 하나. 여러 인덱스 동시 빌드는 엔진에 없음 |
| 1. 병렬도 | `btsort_compute_parallel_degree` `D:src/storage/btree_sort.c:4612-4654` (no-logging: `min(cores, PRM_MAX_PARALLELISM, n_sects)`), `btsort_check_parallelism` `:4665-4714` (n_classes≠1 이거나 섹터 < 병렬도면 직렬) | 워커 수는 섹터 수 이하 |
| 2. 힙 스캔 | 섹터(64페이지, `D:src/storage/storage_common.h:109`) 단위 분배 `get_next_vpid` `D:src/storage/btree_load.c:5680-5775`: 힙 헤더 페이지·bestspace 페이지 건너뜀; `btree_sort_get_next_parallel` `:5778` | 섹터 비트맵의 할당 페이지만, 힙 헤더(fileid 페이지) 제외 |
| 3. 행 거르기·키 추출 | `btree_sort_get_next` `:6141-6408` (병렬판 `:5964-6080` 동일 로직): DELID < oldest 면 건너뜀 `:6264`; 필터 거짓이면 건너뜀 `:6277`; 함수 인덱스는 스냅샷 불만족 행 건너뜀 `:6296`; `heap_attrinfo_generate_key` 로 키; 전부 NULL 키는 트리에 넣지 않고 `n_nulls++` `:6332`; NOT NULL 위반 오류 `:6318`; 키 ≥ `BTREE_MAX_KEYLEN_INPAGE` 면 오버플로 키 페이지 수 누적 | §4.1 |
| 4. 정렬 레코드 | `bt_load_put_buf_to_record` `:3940-4065`: `[hdr 4B][OID 8][class OID 8, unique만][INSID 8?][DELID 8?][key]`, hdr = `length:14|is_bigone:1|has_null:1|key_off:8|flags:8` `D:src/storage/btree_sort.h:49-62` | 메모리 내부 형식. Rust 는 자유 |
| 5. run 정렬 | develop: natural merge `btsort_run_sort` `D:src/storage/btree_sort.c:894`, 비교 `compare_driver` `D:src/storage/btree_load.c:6418-6488` + `bt_load_cmp_key_bytes` `:643-722`. #8209: `btsort_run_pick_sorter` `R:src/storage/btree_sort.c:692-715` 가 radix/merge 선택, 기본값 release `compare` (PR 본문) | §4.2 정렬 순서 |
| 6. run flush | `btsort_run_flush` `D:src/storage/btree_sort.c:1797`, 워커 본체 `btsort_listfile_execute` `:1231` | 임시 파일. Rust 는 자유 |
| 7. shard 분할 | `btsort_px_select_splitters` `:2203-2479` (가중 분위수에서 **서로 다른 키**만, 엄격 증가), `btsort_px_slice_runs_index_leaf` `:2500-2644` (키 < / ≥ splitter) — 같은 키 묶음은 shard 를 넘지 않음 (주석 `:4266-4274`) | 규칙 R-SORT-3 |
| 8. 리프 생성 | shard 워커 `btsort_put_result_index_leaf` `:4044-4242` (k-way merge `:2651-2711`) → `btree_construct_leafs` `D:src/storage/btree_load.c:4986-5097` → 새 키 `bt_load_make_new_record_on_leaf_page` `:4239-4330` / 같은 키 `bt_load_add_same_key_to_record` `:4717-4789` / OID 넘침 `bt_load_nospace_for_new_oid` `:4561-4703` / 디렉터리 `bt_load_finalize_ovf_dir` `:4461-4549` / 오버플로 키 `bt_load_store_overflow_key` `:5155-5231` | §3, §5 |
| 9. 이음매 | `bt_load_patch_seam` `:5481-5555`: 왼쪽 shard 마지막 리프 `next_vpid` ↔ 오른쪽 첫 리프 `prev_vpid`, 마지막 키 < 첫 키 확인 | R-LEAF-6 |
| 10. 비리프 | `bt_load_px_join_finalize` `:5569-5638` → `btree_build_nleafs` `:2178-2723`: PHASE I 리프마다 비리프 레코드 1개 `:2227`, PHASE II 상위 레벨 `:2433`, `btree_connect_page` `:2054-2160` | R-NL-* |
| 11. 루트 | PHASE III `:2575`: 안 쓴 provider 페이지 반환, 오버플로 키가 0개면 미리 만든 오버플로 키 파일 파기 `:2599`, 루트 헤더 작성, **최종 비리프 페이지를 sticky 첫 페이지에 memcpy** `:2686` | R-ROOT-* |
| 12. 내구성 | `pgbuf_flush_all` + `fileio_synchronize_all` + `RVBT_NO_LOGGING_INDEX_DURABLE` `:1816-1833` | Rust 불필요(로그 없음) |

참고: 직렬 경로(`CREATE INDEX` 기본)는 7–9 대신 run 을 하나로 병합해 한 스레드가 로그를 남기며 리프를 만든다(`btsort_merge_run_for_parallel_index_leaf_build` `D:src/storage/btree_sort.c:4397-4526`). 형식은 같다.

## 3. 페이지·레코드 형식

공통: B-tree 파일 `FILE_BTREE`(디스크립터 = class OID + attr id), 루트는 파일의 sticky 첫 페이지 `btree_create_file` `D:src/storage/btree.c:37614-37675`. 새 페이지는 `PAGE_BTREE`, `spage_initialize(UNANCHORED_KEEP_SEQUENCE, align=INT_ALIGNMENT)` `D:src/storage/btree.c:5339-5348`. 슬롯 0 = 헤더, 슬롯 1.. = 레코드(REC_HOME). 페이지 헤더(FILEIO)·슬롯 디렉터리 형식은 R1 범위.

### 3.1 노드 헤더 (리프·비리프, slot 0, `memcpy` host order) — `D:src/storage/btree_load.h:230`, `btree_init_node_header` `D:src/storage/btree_load.c:830-859`

| off | size | 필드 | 11.4 | develop | 변경 |
|---|---|---|---|---|---|
| 0 | 4 | `split_info.pivot` float | 같음 | 0.0 (빌드) | 없음 |
| 4 | 4 | `split_info.index` int | 같음 | 0 | 없음 |
| 8 | 8 | `prev_vpid` (int32 pageid, short volid, pad 2) | 같음 | 리프 체인 | 없음 |
| 16 | 8 | `next_vpid` | 같음 | 리프 체인, 비리프 NULL | 없음 |
| 24 | 2 | `node_level` | 같음 | 리프 1, 비리프 ≥2 | 없음 |
| 26 | 2 | `max_key_len` | 같음 | 페이지 키 최대 길이(오버플로 키는 6) | 없음 |
| 28 | 4 | `common_prefix` | 같음 | 빌드는 0 `D:src/storage/btree_load.c:3536` | 없음 |

크기 32B(계산). `BTREE_IS_PAGE_VALID_LEAF` 가 헤더 레코드 길이 == `sizeof(BTREE_NODE_HEADER)` 로 리프를 판정 `D:src/storage/btree.c:289-295`.

### 3.2 루트 헤더 (루트 slot 0) — `D:src/storage/btree_load.h:242-258`, `11.4:src/storage/btree_load.h:207-226`, `btree_pack_root_header` `D:src/storage/btree_load.c:960-986`

| off | size | 필드 | 11.4 | develop | 변경 커밋 |
|---|---|---|---|---|---|
| 0 | 32 | `node` (3.1) | 같음 | `node_level`=트리 높이 | — |
| 32 | 8 | `num_oids` INT64 | 같음 | unique: 행 수, 그 외 -1 `D:src/storage/btree_load.c:2624-2640` | — |
| 40 | 8 | `num_nulls` INT64 | 같음 | unique: NULL 키 행 수, 그 외 -1 | — |
| 48 | 8 | `num_keys` INT64 | 같음 | unique: 키 수, 그 외 -1 | — |
| 56 | 8 | `topclass_oid` (int pageid, short slotid, short volid) | 같음 | `class_oids[0]` | — |
| 64 | 4 | `unique_pk` | 같음 | bit0 UNIQUE, bit1 PK `D:src/storage/storage_common.h:627-628`; 비유니크 0 | — |
| 68 | 4 | 11.4: `rev_level:16` + `deduplicate_key_idx:16`(idx+1 저장) / develop: `int rev_level` | 비트필드 | 0 (`BTREE_CURRENT_REV_LEVEL` `D:src/storage/btree_load.h:83`) | `5de66400a` #8104 |
| 72 | 8 | `ovfid` VFID (int32 fileid, short volid, pad 2) | 같음 | 오버플로 키 파일, 없으면 NULL | — |
| 80 | 8 | `creator_mvccid` | 같음 | SA/오프라인 = `MVCCID_NULL` `:2651`; NULL 이면 가시성 검사 생략 `D:src/storage/btree.c:19271-19272` | — |
| 88 | 가변 | `packed_key_domain` = `or_put_domain(key_type)` | 11.4 형식 | develop 형식 | `de7bc5ec2` #6486 등이 `or_put_domain` 변경 → R2 |

오프셋은 계산값(`offsetof(packed_key_domain)` = 88). 11.4 비중복 인덱스는 off 68 int 가 0 이라 develop 해석과 같다(11.4 `SET_DECOMPRESS_IDX_HEADER` 에 idx=-1 → 0 저장, `11.4:src/storage/btree_load.c:1919`). DEDUPLICATE 인덱스는 70–71 이 0 이 아니고, 키에 숨은 열 `_dedup_NN` 이 있다(#8104 본문) → Q5.

### 3.3 리프 레코드 — `btree_write_record_header` `D:src/storage/btree.c:4144-4203`, `btree_write_record_ex` `:4318-4402`, 플래그 `:113-128` (11.4 동일 `11.4:src/storage/btree.c:108-125`)

| 위치 | size | 내용 | 조건 |
|---|---|---|---|
| 0 | 4 | 첫 OID pageid (BE) | 항상 |
| 4 | 2 | 첫 OID slotid (BE). 상위 4비트 = 레코드 플래그: FENCE 0x1000, OVERFLOW_OIDS 0x2000, OVERFLOW_KEY 0x4000, CLASS_OID 0x8000 | 항상 |
| 6 | 2 | 첫 OID volid (BE). 상위 2비트 = MVCC 플래그: INSID 0x4000, DELID 0x8000 | 항상 |
| +8 | 8 | class OID (BE) | unique 이고 class ≠ topclass (`CLASS_OID`) |
| +8 | 8 | insert MVCCID (BE) | INSID 비트 |
| +8 | 8 | delete MVCCID (BE) | DELID 비트 |
| k | n | 키 이미지(`key_type->index_writeval`) 또는 오버플로 키 VPID 6B(int pageid BE + short volid BE) | 키 길이 < 2048 이면 일반 `D:src/storage/btree_load.c:3866` |
| — | 0–3 | `or_put_align32` 패딩 | 항상 |
| 이후 | 반복 | 추가 객체: OID 8(MVCC 비트 포함) [+ class OID 8, unique 는 항상] [+ MVCCID] | 같은 키 2번째부터 `:4717-4789` |
| 끝 | 8 | 오버플로 OID 페이지 VPID (pageid BE, volid BE, pad 2) `OR_PUT_VPID_ALIGNED` | `OVERFLOW_OIDS` `D:src/storage/btree.c:2477-2483` |

- 레코드 필드는 `OR_PUT_*` = htonl/htons(big-endian) `D:src/base/object_representation.h:155-165,343-348`. 반면 헤더 구조체(3.1, 3.2, 3.5)와 디렉터리 엔트리는 host order memcpy 다.
- 고정 크기 객체 = unique 32B(OID+classOID+INSID+DELID), 비유니크 24B `BTREE_OBJECT_FIXED_SIZE` `D:src/storage/btree_load.h:151`. unique 의 2번째부터 객체, 오버플로 페이지 객체, 오버플로가 달린 레코드의 첫 객체는 고정 크기(MVCC 비트 둘 다, INSID=`MVCCID_ALL_VISIBLE`(3), DELID=0) `D:src/storage/btree_load.c:4756-4761`, `btree_leaf_record_handle_first_overflow` `D:src/storage/btree.c:3076-3203`.
- 리프 레코드 안 객체 수 상한 = `2048 / fixed_size` (계산: unique 64, 비유니크 85) `D:src/storage/btree_load.h:176`, `D:src/storage/btree_load.c:3915`. 실제 바이트가 더 작아도 개수로 자른다.
- 키 길이는 레코드에 없다. 읽는 쪽은 key domain 의 readval 로 키 끝을 안다(`LEAF_RECORD_SIZE`=0 `D:src/storage/storage_common.h:136`).

### 3.4 비리프 레코드 — `btree_write_fixed_portion_of_non_leaf_record_to_orbuf` `D:src/storage/btree.c:3649-3656`, `btree_connect_page` `D:src/storage/btree_load.c:2054-2160`

| off | size | 내용 |
|---|---|---|
| 0 | 4 | 자식 pageid (BE) |
| 4 | 2 | 자식 volid (BE) |
| 6 | 2 | `key_len` (BE); 오버플로 키면 -1 |
| 8 | n | 구분 키 이미지(`nonleaf_key_type`) 또는 오버플로 키 VPID 6B |
| — | 0–3 | align 4 |

`nonleaf_key_type` = key_type, 단 BIT 만 VARBIT 로 `btree_generate_prefix_domain` `D:src/storage/btree.c:6115-6139` (11.4 동일 `11.4:src/storage/btree.c:5938-5962`).

### 3.5 오버플로 OID 페이지 (같은 B-tree 파일, PAGE_BTREE)

| 항목 | 11.4 | develop unique | develop 비유니크 | 근거 |
|---|---|---|---|---|
| slot 0 헤더 | 8B `{next_vpid}` | 8B `{next_vpid}` | 16B `{next_vpid, dir_vpid}` | `D:src/storage/btree_load.h:262-280`, `:1623`, `10a1df3e6` #7447 |
| 형식 판별 | — | 헤더 레코드 길이 < 16 이면 레거시 | 동일 | `btree_ovf_dir_get_header` `D:src/storage/btree_load.c:1095-1118` |
| slot 1 | 고정 크기 객체 배열 | 32B 객체 배열 | 24B 객체 배열, OID 오름차순 | `:4561-4703` |
| 레코드 최대 | `PAGESIZE - align(SPAGE_HEADER) - align(8)` | 같음 | `- align(16)` | `D:src/storage/btree_load.h:181-185` |
| `dir_vpid` | — | — | 체인이 데이터 페이지 2개 이상이 되면 모든 데이터 페이지에 디렉터리 첫 페이지 VPID, 1개면 NULL | `:4613-4650` |

디렉터리 페이지(비유니크, 체인 ≥2 페이지일 때만): slot 0 = 16B 헤더(`next_vpid` = 다음 디렉터리 페이지, `dir_vpid` NULL), slot 1 = `BTREE_OVF_DIR_ENTRY{OID sep_oid; VPID vpid}` 16B(계산) 배열, host order, 페이지당 최대 `(16384-256)/16 = 1008`개(계산) `D:src/storage/btree_load.h:289-298`, `bt_load_finalize_ovf_dir` `D:src/storage/btree_load.c:4461-4549`. 엔트리 = 체인 순서의 데이터 페이지마다 1개, `sep_oid` = 그 페이지 첫 OID(MVCC 비트 넣기 전) `:4422-4451`, `:4745-4754`.

### 3.6 오버플로 키 파일 (`FILE_BTREE_OVERFLOW_KEY`, PAGE_OVERFLOW, 슬롯 페이지 아님)

| 페이지 | off | size | 필드 |
|---|---|---|---|
| 첫 페이지 | 0 | 8 | `next_vpid` (host order, pad 포함) |
| | 8 | 4 | `length` 키 전체 바이트 (host order) |
| | 12 | ~ | 키 이미지 앞부분 (최대 16384-12) |
| 나머지 | 0 | 8 | `next_vpid` |
| | 8 | ~ | 이어지는 바이트 (최대 16384-8) |

구조체 `D:src/storage/overflow_file.h:38-50`, 기록 `bt_load_store_overflow_key` `D:src/storage/btree_load.c:5155-5231`, ptype `:2795`, 파일 디스크립터(btid + topclass) `btree_create_overflow_key_file` `D:src/storage/btree.c:2037-2069`. `overflow_file.c/.h` 는 11.4..develop 변경 없음(`git diff --stat` 빈 결과).

### 3.7 키 이미지

- 단일 열: `pr_type->index_writeval`. 비교는 `index_cmpdisk` `D:src/storage/btree_load.c:700-712`.
- MIDXKEY: `[nullmap ceil(n/8)B][offset table (n+1)B, 1바이트 오프셋, 255 = 범위 밖][원소들]` `D:src/base/object_representation.h:2653-2800`, `OR_MULTI_MAX_OFFSET` `D:src/base/object_representation_constants.h:176`. nullmap bit=1 이 NOT NULL. 11.4 동일(`11.4:src/base/object_representation.h:2822-2961`).
- 원소 인코딩 변경(CHAR 가변+압축 `83b29b02c` #7164 / `a9fca9002` #7326, NUMERIC `de7bc5ec2` #6486)은 R2(#474) 표를 따른다.
- 리프 키 prefix 압축(`common_prefix`)은 fence 레코드가 있는 MIDXKEY 리프에서만 쓰인다 `D:src/storage/btree.c:4450-4486`, `:16380-16449`. 빌드 경로는 fence 를 만들지 않고 0 을 쓴다. 단 11.4 원본의 DML 로 갈라진 페이지에는 있을 수 있어, 검증기(G3)가 출발 인덱스를 읽을 때 처리해야 한다.

## 4. Rust 가 구현할 규칙 (기계적 검사)

### 4.1 행·키
- R-ROW-1: patch 이후 힙에서 DELID 있는 레코드는 빌드에 넣지 않는다(엔진: DELID < oldest 면 skip `:6264`; 오프라인에선 커밋된 DELID 는 이미 제거됨).
- R-ROW-2: 필터 인덱스면 술어가 TRUE 인 행만 넣는다. 거짓 행은 `n_oids` 에도 세지 않는다 `:6277-6293`.
- R-ROW-3: 키가 NULL 이거나 MIDXKEY 의 모든 열이 NULL 이면 트리에 넣지 않고 `n_oids++`, `n_nulls++` `:6332-6340`. 일부 열만 NULL 이면 넣는다(`has_null`).
- R-ROW-4: `not_null_flag`(PK) 인데 NULL 열이 있으면 빌드 실패 `:6318-6328`.
- R-ROW-5: prefix 인덱스(`attrs_prefix_length`)는 CHAR/BIT 계열만, 지정 길이로 자른 값을 키로 `D:src/object/schema_manager.c:10724-10735`.

### 4.2 정렬 (develop 비교자 = #8209 radix 결과)
- R-SORT-1: 키 비교는 열 순서대로, NULL < non-NULL, 열이 DESC 면 그 열의 결과(NULL 포함)를 뒤집는다 `D:src/storage/btree_load.c:643-722`.
- R-SORT-2: 키가 같으면 OID 오름차순, OID 순서는 (volid, pageid, slotid) `D:src/storage/oid.h:110-113`, `D:src/storage/btree_load.c:6476-6486`. 같은 OID 가 두 번 나오면 결함.
- R-SORT-3: 병렬 분할 시 경계는 서로 다른 키로만 자른다(같은 키의 OID 가 두 shard 로 갈라지면 안 됨) `D:src/storage/btree_sort.c:4266-4274`.
- R-SORT-4 (radix 를 옮길 경우): `RADIX_KEY_FORMAT` 별 정규화 — signed 는 부호 비트 반전, IEEE 는 음수면 전 비트 반전, DESC 는 보수, 문자열은 콜레이션 7종만, MIDXKEY 는 앞 열부터 64 word 까지 `R:src/storage/btree_sort_radix.hpp:38-70`. 결과는 R-SORT-1/2 와 같아야 한다(PR 본문의 검증 조건).

### 4.3 리프
- R-LEAF-1: 키 하나 = 리프 레코드 하나(+오버플로 체인). 키 이미지 길이 ≥ 2048(16K 페이지, `BTREE_MAX_KEYLEN_INPAGE`)이면 오버플로 키(§3.6) + `OVERFLOW_KEY` 플래그 + 6B VPID.
- R-LEAF-2: 첫 객체 다음 OID 를 붙이다 개수가 64/85(§3.3)를 넘으면 오버플로 OID 페이지를 열고, 리프 레코드 끝에 VPID 8B 를 붙이고 `OVERFLOW_OIDS` 를 세우고 첫 객체를 고정 크기로 바꾼다.
- R-LEAF-3: 오버플로 페이지 한 레코드의 객체 수 상한 = `spage_max_space_for_new_record(그 페이지) / fixed_size` `:4699-4700` (값은 Q2).
- R-LEAF-4: 새 레코드를 넣기 전, `(남은 최대 공간 - 레코드 길이) < 16384*0.05 + 6 = 825.2`(계산, `index_unfill_factor` 기본 0.05 `D:src/base/system_parameter.c:1256-1263`) 이고 페이지에 키 레코드가 1개 이상이면 새 리프 `:4248-4259`.
- R-LEAF-5: 리프 헤더 `max_key_len` = 페이지 키 길이 최대(오버플로 키는 6) `:4270-4282`.
- R-LEAF-6: 리프 `prev_vpid/next_vpid` 이중 연결, 첫 리프 prev NULL, 마지막 next NULL, shard 경계도 연결 `:5481-5555`.
- R-LEAF-7 (unique): 같은 키에 보이는 OID 가 2개 이상이면 유니크 위반 오류 `D:src/storage/btree_load.c:4393-4407`.

### 4.4 비리프·루트
- R-NL-1: 레벨 2 는 리프 페이지마다 레코드 1개(자식 = 그 리프). 키: 문자열/MIDXKEY 면 첫 리프는 그 첫 키, 이후는 `prefix(앞 리프 마지막 키, 이 리프 첫 키)`; 그 밖의 타입은 이 리프 첫 키 `:2255-2410`, `btree_get_prefix_separator` `D:src/storage/btree.c:15793-15850`. 검사: `앞 마지막 키 < sep ≤ 이 첫 키`.
- R-NL-2: 레벨 ≥3 은 아래 레벨 페이지마다 그 페이지 첫 키 `:2433-2573`, `:2520`.
- R-NL-3: 비리프 페이지 채움 임계 `16384*max(0.05,0.1)+6 = 1644.4`(계산) `D:src/storage/btree_load.h:91-93`, `:2100`.
- R-NL-4: 레벨 하나에 페이지가 1개가 될 때까지 반복; 리프가 1장이어도 루트는 비리프(level ≥2) `:2227-2255`.
- R-ROOT-1: 최종 비리프 페이지 내용을 sticky 첫 페이지(`BTID.root_pageid`)에 쓰고 slot 0 을 루트 헤더로 교체 `:2662-2693`. 엔진은 원래 상위 페이지를 할당된 채 남긴다(같은 위치). Rust 는 처음부터 루트 페이지에 써도 된다(추론).
- R-ROOT-2: unique 면 통계 3개(§3.2), 비유니크 -1·`unique_pk`=0; `rev_level`=0; `creator_mvccid`=0; 오버플로 키가 없으면 `ovfid` NULL·파일 없음 `:2590-2601`.

### 4.5 MVCC (오프라인)
- R-MVCC-1: 입력이 전부 all-visible 이면 정렬 레코드 flags=0, 리프 첫 객체 MVCC 비트 0, 고정 크기 위치만 INSID=3/DELID=0 `:3961-3972`, `D:src/storage/btree.c:4172-4193`. vacuum 알림(`bt_load_notify_to_vacuum` `:4803`) 대상 없음.

## 5. 인덱스 종류별 추가 요구

| 종류 | 형식 | 추가 처리 | 근거 |
|---|---|---|---|
| PK | unique(bit0\|bit1=3), 32B 객체, 레거시 8B 오버플로 헤더 | NOT NULL 검사, 루트 통계, 유니크 위반 검사 | `:1623`, `:6318`, `:2624-2632` |
| UNIQUE | bit0=1 | NULL 허용(트리 밖, `num_nulls`), 나머지 PK 와 같음 | 같음 |
| 일반 / 역(DESC) 인덱스 | 비유니크, 24B 객체, 16B 디렉터리 체인 | DESC 는 key domain `is_desc` 로 정렬만 반대 | `:1623`, `D:src/storage/btree_load.c:700-712` |
| FK | 비유니크 | 빌드 뒤 FK 키마다 PK 인덱스 대조(파티션 PK 는 pruning 포함), DESC PK 대응 `66a2dcb90` #8129 / `05e6798f0` #8054. 같은 이름 공유(`shared_cons_name`)면 BTID 를 공유해 한 번만 빌드 | `btree_load_check_fk` `D:src/storage/btree_load.c:6706-7124`, `D:src/object/schema_manager.c:11279-11283` |
| 함수 인덱스 | key domain = 함수 결과(단일) 또는 col_id 위치에 함수 결과를 넣은 MIDXKEY | XASL `expr_stream` 을 행마다 평가 | `D:src/object/schema_manager.c:10743-10757`, `:1538-1552`, `:6296` → Q1 |
| 필터 인덱스 | 일반과 같음 | XASL `pred_stream` 평가, 거짓 행 제외 | `:1524-1537`, `:6277` → Q1 |
| 파티션 테이블 | 파티션마다 별도 BTID·파일(n_classes=1) | 유니크/PK 는 파티션 키 포함 강제(-1169); 일반·FK 는 항상 로컬 | `D:src/object/schema_manager.c:11211-11237`, `:16219-16290`; 병렬 조건 `D:src/storage/btree_sort.c:4672-4677` |
| 상속(n_classes>1) | unique 에서 class OID 플래그 | 지도 범위 밖(superclass 미사용) | `D:src/storage/btree.c:4160-4170`, `D:src/storage/btree_load.c:6215-6218` |

## 6. 기준선 (#433, develop `8f57aa0d7` release, 1천만 행 `t(id INT, v VARCHAR(255))`, v 1,200,021,329B, 병렬도 16, cold start, 3회 중앙값)

| 방식 | DWB 켬 | DWB 끔 | 인덱스 페이지 |
|---|---|---|---|
| A. `CREATE INDEX` (기본, 정렬 워커 8) | 15.1s | 13.7s | 87,450 |
| B. A + 병렬도 16 강제 | 14.5s | 13.2s | 87,445 |
| C. `loaddb -C -i ... --no-logging-index` | 10.4s | 5.9s | 87,450 |
| D. `WITH ONLINE PARALLEL 16` | 96.3s | 58.8s | ~121,150 |

- A/B 는 리프를 한 스레드가 로그를 남기며 만드는 ~9s 직렬 구간이 지배한다. C 의 DWB 켬 꼬리는 워커 16개가 `dwb_set_data_on_next_slot` 대기(Num_DWB_wait_flush_block 20,018회, 171.8s 합). 같은 데이터에서 영구 임시 볼륨이 있으면 C 가 1.8배 느려진다(보상 fsync). 출처: #433 본문과 댓글 1–4.
- Rust 비교 기준선 제안: C(DWB 끔) 5.9s. 단 #433 은 non-unique varchar 한 모양뿐이다.

## 열린 질문

- Q1. 함수·필터 인덱스: 카탈로그에 저장된 XASL 직렬화 식을 Rust 가 평가해야 한다. 기준 DB 에 나오는 함수만 평가기를 구현할지, 이 두 종류만 엔진(develop `cubrid loaddb -i`)에 맡길지 결정해야 한다.
- Q2. 오버플로 OID 레코드 용량 `spage_max_space_for_new_record` 의 정확한 값(슬롯 페이지 헤더·슬롯 4B·정렬 반영)은 R1 의 slotted page 표에서 확정해야 한다. 이 문서는 계산하지 않았다.
- Q3. 엔진은 no-logging 페이지의 LSA 를 갱신하지 않는다(`btree_log_page` `D:src/storage/btree_load.c:2740-2789`). 새 로그를 쓰는 도착 DB 에서 Rust 가 만든 페이지 LSA 를 무엇으로 둘지는 R1/R5 가 정한다.
- Q4. BTID 를 클래스 객체 제약 속성, catalog representation 의 btree 통계, `_db_index` 에 등록하는 일과 loaddb 가 빌드 뒤 돌리는 통계 갱신은 R3/R4/G2 범위다. 이 문서는 확인하지 않았다.
- Q5. 11.4 DEDUPLICATE 인덱스(숨은 `_dedup_NN` 열, off 68 상위 16비트)는 develop 에서 숨은 열 없이 재빌드해야 한다(#8104). 카탈로그에서 그 열을 빼는 규칙은 R3/R4 가 정한다. 11.4 기본값 -1(꺼짐)이라 기준 DB 에는 없을 가능성이 높다(PR 본문, 미검증).
- Q6. 파티션 부모 클래스(파티션된 테이블 자체)에 실제 B-tree 파일이 있는지, BTID 가 NULL 인지 확인하지 못했다(`D:src/object/schema_manager.c:12163-12167` 주석은 PK 의 NULL BTID 를 암시). T1(#479) 기준 DB 로 확인해야 한다.
- Q7. 비리프 구분 키를 엔진처럼 최소 prefix 로 만들지, 항상 오른쪽 첫 키로 둘지(R-NL-1 검사는 둘 다 통과, 페이지 수만 다름). 엔진과 바이트가 같아야 하는지는 G3 검증 방식이 정한다.
- Q8. FK 대조(`btree_load_check_fk`)를 Rust 빌드에서 다시 할지, 출발 DB 가 이미 일관적이라고 보고 검증기(G3)에만 둘지.
- Q9. #8209 는 미머지(OPEN, head `fec3f773a`)이고 release 기본값이 `compare` 다. Rust 가 radix 를 쓰는 것은 엔진 형식과 무관하므로 성능 판단만 남는다.

## Sources

- develop `5b1867174`: `src/storage/btree_load.c`, `src/storage/btree_load.h`, `src/storage/btree_sort.c`, `src/storage/btree_sort.h`, `src/storage/btree.c`, `src/storage/btree.h`, `src/storage/storage_common.h`, `src/storage/overflow_file.h`, `src/storage/oid.h`, `src/base/object_representation.h`, `src/base/object_representation_constants.h`, `src/base/system_parameter.c`, `src/object/schema_manager.c`, `src/communication/network_interface_sr.cpp`, `src/loaddb/load_db.c`, `src/compat/dbtype_def.h:957-968,1046-1051`.
- release/11.4 `46212adcd`: `src/storage/btree_load.h`, `src/storage/btree_load.c`, `src/storage/btree.c`, `src/storage/storage_common.h`, `src/base/object_representation.h`.
- 커밋/PR: `1aa79a03b` #7504 (CBRD-27071 no-logging 병렬 빌드), `cc563c7fd` #7011 (CBRD-26678 병렬 인덱스 빌드), `6faddec23` #7831 (CBRD-27235 인덱스 빌드 정렬 분리), `dcfe7981c` #7846, `a9f075586` #8021, `10a1df3e6` #7447 (CBRD-24094 OID 디렉터리), `0c310e25c` #7899 (CBRD-27401 COMPACT), `5de66400a` #8104 (CBRD-27324 DEDUPLICATE 제거), `66a2dcb90` #8129 (CBRD-27592), `05e6798f0` #8054 (CBRD-27516), `de7bc5ec2` #6486 (CBRD-26006 NUMERIC), `83b29b02c` #7164 / `a9fca9002` #7326 (CHAR), PR #8209 head `fec3f773a` (CBRD-27381 MSD radix, OPEN): `src/storage/btree_sort_radix.hpp`, `src/storage/btree_sort.c:692-715`, PR 본문.
- 측정: xmilex-git/workspace #433 본문·댓글.
- 11.4 포함 여부: `git merge-base --is-ancestor` 로 `1aa79a03b`, `cc563c7fd`, `10a1df3e6` 가 `origin/release/11.4` 의 조상이 아님을 확인.
