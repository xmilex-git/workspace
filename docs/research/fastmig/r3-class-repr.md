# R3 — 클래스 객체 디스크 포맷과 representation 디렉터리: 11.4 → develop 같은 슬롯 재기록 규칙 (#475)

기준 커밋: **D** = develop `5b1867174`, **R** = `origin/release/11.4` `46212adcd`. 인용 `D:path:line`, `R:path:line`.
"계산값"이라고 적은 오프셋·크기는 구조체·매크로에서 산술로 유도한 값이고 엔진 주석에서 그대로 읽은 값이 아니다.

## 1. 요약 답

1. 클래스 레코드 **골격은 그대로다**: 헤더 8B, var 오프셋 테이블 17+1개, fixed 88B, ORC_* 오프셋·인덱스가 두 선에서 바이트 단위로 같다 (R/D `object_representation.h` ORC enum 블록 diff 0줄, D:src/base/object_representation.h:782-823). rep_dir OID @88, HFID @96, owner @152 (계산값).
2. 클래스 레코드 **내용**은 다섯 곳이 다르다. (a) partition 하위구조 fixed에 `class_partition_type` int가 추가돼 4B→8B (1f1263217, PR #6443; D:src/object/transform_cl.c:4905). (b) 제약 property 시퀀스 꼬리가 `{…, status, comment}`에서 `{…, status, index_type, options, comment}`로 바뀌었다 (1f1263217; D:src/storage/storage_common.h:1033-1043). (c) FK info 시퀀스가 4원소에서 5원소가 됐다 (`ref_match_option`). (d) filter predicate stream의 타입이 CHAR에서 VARCHAR가 됐다. (e) CHAR/NUMERIC 기본값·partition 값이 새 값 인코딩을 쓴다.
3. 클래스 객체 안의 문자열(name, comment 등)은 11.4가 `tp_VarNChar`로, develop이 `tp_String`으로 쓰지만 **바이트가 같다**. 둘 다 `pr_write_[un]compressed_string_to_buffer`를 INT_ALIGNMENT로 호출한다 (R:src/object/transform_cl.c:1572, D:src/object/transform_cl.c:1547; bb8f3cbda, PR #6420).
4. representation 디렉터리(`system_catalog.c`)에서는 **BTREE_STATS가 80B에서 120B가 되고**(INT64 keys/pkeys), **CLS_INFO의 행 수가 @16 int에서 @32 INT64로 옮겨졌다** (519cc1a43, PR #7856). develop은 V0(80B)를 읽지 못한다. 커밋 본문은 "in place 마이그레이션 불가"라고 밝힌다 (07aec2c5c, PR #7957). 디렉터리 레코드(2 item × 16B), DISK_REPR 56B, DISK_ATTR 88B는 같다.
5. catalog 디렉터리는 **클래스당 class-info item과 "마지막 repr" item 두 개만** 담는다 (D:src/storage/system_catalog.c:2034). 옛 repid의 레이아웃은 catalog이 아니라 **클래스 레코드의 `representations` 집합**(ORC_REPRESENTATIONS_INDEX)에서 해석된다 (D:src/base/object_representation_sr.c:2883-3060, heap_file.c:2042). DISK_REPR는 새 클래스 레코드만으로 전부 유도된다 (`orc_diskrep_from_record`, D:src/base/object_representation_sr.c:193).
6. 사용자 힙 레코드의 옛 repid가 그대로 해석되려면 다음 세 가지를 보존해야 한다. ① 클래스 repid 번호(헤더 하위 24비트). ② 현재 rep의 attribute 집합 순서·id·`fixed_count`/`variable_count`/`fixed_size`. ③ `representations` 집합의 각 rep: id, n_fixed/n_variable, rep_attribute 순서·attid·type·domain. 세 가지 모두 develop 해석 규칙과 맞아야 한다.
7. ③이 깨지는 유일한 원인은 **CHAR·NUMERIC의 `variable_p`가 0에서 1로 바뀐 것**이다 (R:src/object/object_primitive.c:1694,12303 → D:src/object/object_primitive.c:1656,12695). 고정 영역 위치는 `i < n_fixed`와 `tp_domain_disk_size` 누적으로 계산되므로 (D:src/base/object_representation_sr.c:2525-2535, 3025-3033), CHAR/NUMERIC이 고정 영역에 있는 rep는 develop에서 오독된다. 따라서 어떤 rep에든 CHAR/NUMERIC/NCHAR가 있는 클래스는 **transform 클래스**다. 그 밖의 PR_TYPE 헤더(variable_p, disksize, alignment)는 diff가 0이다.
8. 재기록 때 레코드가 커지면 엔진의 `heap_update_home`/`_relocation`/`_bigone` 규칙(D:src/storage/heap_file.c:23238, 22912, 22692)을 그대로 따른다. 여기에 쓰는 big 임계값은 **develop 식**이고, 16K 페이지에서 16236B(계산값)다. 11.4 식은 16012B였다(계산값; e84a7f6dc, PR #7353).
9. 클래스 레코드 안의 OID 중 BTID(인덱스 재빌드), rep_dir(catalog 재생성), owner(`db_user`→`_db_user`), triggers(`db_trigger`→`_db_trigger`)는 **재매핑 대상**이다 (8ba543178, PR #6903). HFID와 클래스 OID, super/sub 클래스 OID는 배치 보존 원칙상 그대로다.
10. 결론: 클래스 레코드는 "develop `tf_class_to_disk`가 썼을 바이트"로 재직렬화하고, catalog은 그 레코드에서 `orc_diskrep_from_record` 규칙으로 새로 만든다. 옛 catalog 바이트를 패치하는 방식은 쓰지 않는다.

## 2. 클래스 객체 레코드 (root 힙) 레이아웃

root 클래스는 MVCC 비활성이다 (D:src/transaction/mvcc.c:687-691). 그래서 클래스 레코드는 비-MVCC 8B 헤더를 쓴다. 정수 필드는 모두 `OR_PUT_INT`(htonl, 빅엔디언)다 (D:src/base/object_representation.h:161-162). OID 필드는 `OR_PUT_OID` 순서(pageid 4, slotid 2, volid 2)를 따른다 (같은 파일 343-348).

### 2.1 헤더·var 테이블·fixed (레코드 시작 기준, 계산값)

| offset | size | 필드 | 11.4 | develop | 근거 |
|---|---|---|---|---|---|
| 0 | 4 | repid word = `class_->repid` \| `OR_OFFSET_SIZE_4BYTE`(0x60000000), MVCC flag 0 | 같음 | 같음 | D:src/object/transform_cl.c:4510-4517; D:src/base/object_representation_constants.h:153-161 |
| 4 | 4 | CHN | 같음 | 같음 | 같은 위치 |
| 8 | 72 | var 오프셋 테이블 (17 var + end, 4B씩; var 테이블 시작 기준 상대값) | 같음 | 같음 | `OR_VAR_TABLE_SIZE` D:src/base/object_representation.h:496-499; put_class_varinfo D:src/object/transform_cl.c:3588 |
| 80 | 4 | att_ids | = | = | ORC enum D:src/base/object_representation.h:782-797, put_class_attributes D:src/object/transform_cl.c:3677 |
| 84 | 4 | method_ids | = | = | 〃 |
| 88 | 8 | **ch_rep_dir OID** (`ORC_REP_DIR_OFFSET`=8) | 옛 catalog | **새 catalog dir OID로 교체** | D:src/object/transform_cl.c:3694; R:src/object/transform_cl.c:3675 |
| 96 / 100 / 104 | 4×3 | HFID fileid / volid / hpgid | 보존 | 보존 | 〃 |
| 108 / 112 / 116 | 4×3 | fixed_count / variable_count / fixed_size | 11.4 값 | transform 클래스면 재계산 | 〃 |
| 120 | 4 | att_count | = | = | |
| 124 | 4 | object_size (항상 0) | 0 | 0 | |
| 128..140 | 4×4 | shared / method / class_method / class_attr count | = | = | |
| 144 | 4 | flags (`SM_CLASSFLAG_*`) | = | = | |
| 148 | 4 | class_type | = | = | |
| 152 | 8 | **owner OID** | `db_user` 행 | `_db_user` 행 OID로 재매핑 | D:src/object/transform_cl.c:3714; 이름 D:src/object/schema_system_catalog_constants.h:47 |
| 160 | 4 | collation_id | = | = | |
| 164 | 4 | tde_algorithm (`ORC_CLASS_TDE_ALGORITHM`=84) | = | = | |
| 168 | — | variable 영역 시작 (fixed 88B = int 18개 + OID 2개, 계산값) | | | class_atts D:src/object/transform.c:185; `mc_fixed_size` D:src/object/transform.c:612 |

### 2.2 variable 속성 (ORC_*_INDEX, 두 선 동일)

| idx | 이름 | 형식 | 11.4→develop 차이 |
|---|---|---|---|
| 0 | name (unique_name `owner.class`) | 문자열 | 바이트 동일 (요약 3) |
| 1 | loader_commands | 문자열 | 동일 |
| 2 | **representations** | substructure set (rep: var 2 + fixed id/fixed_count/variable_count/0; rep_attr: var 1 + fixed attid/typeid + domain set) | 형식 동일 (D:src/object/transform_cl.c:3325, 3450). transform 클래스는 내용을 다시 써야 한다 (규칙 C) |
| 3 | sub_classes (users) | OID set | 보존 |
| 4 | super_classes (inheritance) | OID set | 보존 |
| 5 | attributes | substructure set | 형식 동일 (D:src/object/transform_cl.c:2870). 기본값 `or_put_value`(2938)는 값 인코딩을 따른다 |
| 6, 7 | shared / class attrs | 〃 | 〃 |
| 8..11 | methods / class_methods / method_files / resolutions | | 동일 |
| 12 | query_spec | substructure set | 동일 |
| 13 | **triggers** | OID set | `_db_trigger` 행 OID로 재매핑 (D:src/object/transform_cl.c:3760) |
| 14 | **properties** | DB_SEQ (값 태그 포함) | 제약 시퀀스 변경, BTID 교체 (표 2.4) |
| 15 | comment | 문자열 | 동일 |
| 16 | **partition** | substructure set | fixed +4B (표 2.3) |

substructure set 형식: set 헤더 8B, offset 테이블 `OR_VAR_TABLE_SIZE(count)`, domain 길이 4B, sub-domain 4B, 공통 sub 헤더(OID 8 + repid 4 + flags 4), 요소 순서로 이어진다 (D:src/object/transform_cl.c:1783-1830).

### 2.3 partition 요소 (요소 시작 기준, 계산값)

| offset | size | 11.4 | develop | 변경 |
|---|---|---|---|---|
| 0 | 20 | var 테이블 (pname, pexpr, pvalues, comment, end) | 같음 | — |
| 20 | 4 | ptype | ptype | — |
| 24 | 4 | (var 데이터 시작) | **class_partition_type** (0/1/2) | 1f1263217, PR #6443 (D:src/object/transform_cl.c:4905; meta D:src/object/transform.c:239-241; R:src/object/transform_cl.c:4904, R:src/object/transform.c:237-238) |
| 24 / 28 | … | pname, pexpr, pvalues(seq), comment | 4B 뒤로 밀림 | var 오프셋 전부 +4 |

`class_partition_type`의 값은 `pname == NULL`이면 `DB_PARTITIONED_CLASS`(1), 아니면 `DB_PARTITION_CLASS`(2)다 (D:src/query/execute_schema.c:16355-16365; 열거값 D:src/storage/storage_common.h:1245-1250). develop reader는 1..2만 허용한다 (D:src/object/transform_cl.c:4998-4999). 메타클래스 repid는 바뀌지 않았으므로 reader가 옛 요소를 식별할 방법이 없다. 따라서 partition을 가진 클래스(부모와 각 partition)는 **반드시 재기록**한다.

### 2.4 properties 제약 시퀀스

| 항목 | 11.4 | develop | 근거 |
|---|---|---|---|
| 제약 info | `{BTID, [att, asc_desc]…, optional?, status, comment}` (R:src/object/class_object.c:972-1215, status@1210) | `{BTID, [att, asc_desc]…, optional?, status, index_type, options, comment}`. 끝에서 거꾸로 셌을 때 COMMENT=1, OPTIONS=2, INDEX_TYPE=3, STATUS=4, OPTIONAL=5 | D:src/storage/storage_common.h:1033-1043, D:src/object/class_object.c:1203-1211; 1f1263217 |
| index_type / options 값 | — | `SM_BTREE_TYPE`(0) / 0 | D:src/object/class_object.h `SM_INDEX_TYPE`, `options /* reserved */` |
| FK info | 4원소 (ref_class_oid, pk_btid, delete, update) (R:src/object/class_object.c:669) | 5원소 (+`ref_match_option`, 기본 `SM_FK_MATCH_NONE`=0) | D:src/object/class_object.c:671-697, 2784-2788; D:src/storage/storage_common.h:1047-1055, 1117-1123; D:src/compat/db_temp.c:538 |
| filter pred stream | `db_make_char` (R:src/object/class_object.c:842) | `db_make_varchar` (D:src/object/class_object.c:847) | CHAR 인코딩 변경 때문에 VARCHAR로 다시 써야 한다 |
| dedup 의사 속성 `_dedup_NN` (id `0x8A8B8C90-level`) | 인덱스별 DEDUPLICATE 옵션이면 존재 (기본 sysparam은 비활성) (R:src/object/deduplicate_key.h:36-80) | 기능 삭제 | 5de66400a, PR #8104 |
| BTID 문자열 `volid\|pageid\|fileid`, pk_btid | 옛 인덱스 | 재빌드한 인덱스 BTID로 교체 | 지도 Notes "인덱스 전부 재빌드" |

## 3. representation 디렉터리 (`system_catalog.c`) 레이아웃

catalog 페이지는 `PAGE_CATALOG`, `ANCHORED_DONT_REUSE_SLOTS`, alignment `MAX_ALIGNMENT`로 만들어진다. slot 0은 페이지 헤더 레코드다 (D:src/storage/system_catalog.c:612-650).

| 구조 | offset | size | 11.4 | develop | 변경 커밋 |
|---|---|---|---|---|---|
| 페이지 헤더 (slot 0) | 0 ovf pageid / 4 ovf volid / 8 dir_count / 12 is_overflow | 16 | 같음 | 같음 (D:…system_catalog.c:65-70) | — |
| repr 디렉터리 레코드 | item0 @0, item1 @16 | 32 | 같음 | 같음 | — |
| └ REPR_ITEM | 0 pageid(4) / 4 volid(2) / 8 repr_id(2) / 10 slotid(2) / 12 count(1, item0만) | 16 | 같음 (R:…:140-146) | 같음 (D:…:149-155) | — |
| CLS_INFO | 0 HFID(12) / 12 tot_pages / 16 tot_objs / 20 time_stamp / 24 rep_dir OID | 56 | 32..55 reserved 0 (R:…:132-138) | **16 = 0 (읽지 않음), 32 = tot_objs INT64**, 40..55 zero (D:…:139-147, 530-541) | 519cc1a43 PR #7856, 07aec2c5c PR #7957 |
| DISK_REPR | 0 id / 4 n_fixed / 8 fixed_length / 12 n_variable / 16 reserved_1 = 0 | 56 | 같음 (R:…:98-103) | 같음 (D:…:99-104, 423-432). 20..55는 엔진이 쓰지 않는다 | — |
| DISK_ATTR | 0 id / 4 location / 8 type / 12 val_length / 16 position / 20 classoid(8) / 28 n_btstats / 80 ndv INT64 | 88 | 같음 (R:…:117) | 같음 (D:…:110-118) | — |
| └ 기본값 바이트 | DISK_ATTR 바로 뒤 | val_length | 11.4 인코딩 | develop 인코딩 (`orc_diskrep_from_record`, D:src/base/object_representation_sr.c:193) | CHAR/NUMERIC이면 변경 |
| BT_STATS | 0 BTID(10+2) / 12 leafs / 16 pages / 20 height / 24 keys(int) / 28 has_function / 32 pkeys int×8 / 64 reserved int×4 | **80** (R:…:119-127) | — | — | — |
| BT_STATS | 0..31 같음, **24 = 0** / **32 keys INT64** / **40 pkeys INT64×8** / **104 reserved int×4** | — | — | **120** (D:…:120-134, 488-515) | 519cc1a43 PR #7856; V0 reader 삭제 07aec2c5c PR #7957 |

레코드 분할 규칙(두 선 동일): 하나의 repr 레코드는 DISK_REPR, (DISK_ATTR, 기본값, BT_STATS×n_btstats)×속성 순으로 이어진다. 각 구조체는 현재 페이지 조각의 남은 공간보다 크면 쪼개지지 않고 다음 overflow 페이지로 넘어간다. 기본값만 예외로 여러 페이지에 걸칠 수 있다 (D:src/storage/system_catalog.c:1100-1330). 조각 크기는 `spage_max_space_for_new_record - CATALOG_MAX_SLOT_ID_SIZE(12)`이다 (D:…:2912). BT_STATS 크기가 바뀌었으므로 **조각 경계가 달라진다**. 그래서 바이트 단위 제자리 확장은 불가하고 재생성만 가능하다.

## 4. 같은 슬롯 재기록: REC_RELOCATION / REC_BIGONE 전환

| 항목 | 11.4 | develop | 근거 |
|---|---|---|---|
| `spage_max_record_size` | DB_PAGESIZE − 32 − 4 | 같음 | D:src/storage/slotted_page.c:841-844; SPAGE_HEADER 32B·SLOT 4B (D:src/storage/slotted_page.h:63-91, 계산값) |
| DB_PAGESIZE | IO_PAGESIZE − 40 | 같음 | D:src/storage/storage_common.c:44; FILEIO_PAGE_RESERVED 32B + WATERMARK 8B (D:src/storage/file_io.h:166-182, 계산값) |
| `heap_Maxslotted_reclength` | `spage_max − sizeof(HEAP_HDR_STATS)`(296B, 계산값) → 16K에서 **16012** | `ALIGN_DOWN4(spage_max − ALIGN4(sizeof(HEAP_CHAIN)=40) − 8×4)` → 16K에서 **16236** | R:src/storage/heap_file.c:5122-5124; D:src/storage/heap_file.c:3742-3744; e84a7f6dc PR #7353 |
| forwarding 레코드 | `sizeof(OID)`=8B, **네이티브 struct**(pageid, slotid, volid; OR_PUT 아님) | 같음 | D:src/storage/heap_file.c:20700-20709; OID struct D:src/compat/dbtype_def.h:1046-1051 |
| BIGONE 포인터 | ovf 첫 페이지 VPID, slotid = NULL_SLOTID(-1) | 같음 | D:src/storage/heap_file.c:6161-6176 |
| overflow 페이지 | 첫 페이지 `{VPID next, int length, data}`(data @12), 나머지 `{VPID next, data}`(data @8), `PAGE_OVERFLOW` | 같음 (overflow_file.[ch] diff 0) | D:src/storage/overflow_file.h:38-50 |
| REC_* 값 | ASSIGN 1, HOME 2, NEWHOME 3, RELOCATION 4, BIGONE 5, MARKDELETED 6, DELETED_WILL_REUSE 7 | 같음 | D:src/storage/storage_common.h:1178-1200 |

## 5. Rust 도구가 구현할 규칙 (기계적 검사)

**A. 클래스 분류 (클래스마다 1회 결정)**
- A1. 현재 rep(attributes 집합)와 `representations`의 모든 rep_attribute를 훑는다. type ∈ {CHAR 25, NUMERIC 22} 또는 domain에 그 타입이 있으면 `TRANSFORM`, 아니면 `KEEP`으로 정한다. 근거는 요약 7이다.
- A2. type ∈ {26, 27}(NCHAR/VARNCHAR)이면 **중단**한다. develop에서는 `DB_TYPE_*_DEPRECATED`이고 pack/unpack 분기가 삭제됐다 (D:src/compat/dbtype_def.h:779; bb8f3cbda PR #6420). 처리 방침은 미결이다 (§6).
- A3. 제약 시퀀스에 `_dedup_` 이름 또는 dedup id 범위 속성이 있으면 그 [att, asc_desc] 쌍을 지운다. 해당 인덱스는 재빌드 대상이다.

**B. KEEP 클래스: repid와 레이아웃을 바이트 보존**
- B1. 헤더 repid word, CHN, fixed 오프셋 80..167을 그대로 둔다. 바꾸는 것은 rep_dir OID(@88)와 owner OID(@152) 두 필드뿐이다.
- B2. attributes·representations 하위구조는 바이트 그대로 복사한다. 순서, attid, n_fixed/n_variable, domain 모두 불변이다.
- B3. 사용자 힙 레코드는 repid를 그대로 둔다. copy/patch 대상이다.

**C. TRANSFORM 클래스: 레이아웃 재정의 + 레코드 재인코딩**
- C1. 새 attribute 순서는 `build_storage_order`를 따른다. develop `variable_p` 기준으로 fixed와 variable 그룹으로 나눈다. fixed 그룹은 alignment 내림차순, 같은 alignment 안에서는 `tp_domain_disk_size` 오름차순으로 정렬한다. variable 그룹은 기존 상대 순서를 유지한다 (D:src/object/schema_manager.c:9962-9993, 10022-10120). partition 자식은 부모와 같은 순서와 id를 써야 한다 (같은 파일 10128-10162).
- C2. `fixed_count`, `variable_count`, `fixed_size = DB_ATT_ALIGN(Σ fixed disk size)`를 다시 계산한다 (D:src/base/object_representation_sr.c:2525-2560).
- C3. 그 클래스의 모든 힙 레코드(옛 repid 포함)를 develop 인코딩의 **현재 repid**로 재인코딩한다. 같은 OID를 쓰고, 커지면 규칙 D를 따른다. 그다음 `representations` 집합에서 옛 rep를 제거한다. 남은 레코드가 옛 repid를 갖지 않으면 엔진이 그 rep를 찾을 일이 없다 (`ER_CT_UNKNOWN_REPRID`는 실제로 찾을 때만 난다, D:src/base/object_representation_sr.c:2933-2936). repid 번호는 유지한다.
- C4. attribute 기본값(current/original), shared/class attr 값, partition `pvalues` 안의 CHAR/NUMERIC 원소를 develop `tp_Char`/`tp_Numeric` writer로 재인코딩한다 (D:src/object/object_primitive.c:12130, 8722).

**D. 레코드 배치 (재직렬화 길이 `L`, 옛 home 타입별, 오프라인이라 saved space 0)**
- D0. `fits(page, slot, L)` ⇔ `L + waste(L) − (old_len + waste(old_len)) ≤ total_free`이다. waste는 페이지 alignment 기준이고 `L ≤ spage_max`여야 한다 (D:src/storage/slotted_page.c:2193-2240).
- D1. home=REC_HOME: `L > maxslotted_dev`면 ovf 삽입 후 home=REC_BIGONE(8B). 그렇지 않고 `!fits(home)`이면 다른 페이지에 REC_NEWHOME을 삽입하고 home=REC_RELOCATION(8B). 둘 다 아니면 home에 REC_HOME으로 그대로 쓴다 (D:src/storage/heap_file.c:23290-23376).
- D2. home=REC_RELOCATION: big이면 ovf 삽입, home=BIGONE, 옛 NEWHOME 삭제. `!fits(fwd) && !fits(home)`이면 새 NEWHOME, home=RELOCATION, 옛 NEWHOME 삭제. `fits(home)`이면 home=REC_HOME, 옛 NEWHOME 삭제. 남은 경우는 옛 NEWHOME 자리 갱신이다. 이 우선순위를 그대로 따른다 (D:src/storage/heap_file.c:22955-23070).
- D3. home=REC_BIGONE: big이면 ovf를 제자리 갱신한다. home slot에 들어가면 home=REC_HOME으로 바꾸고 ovf를 해제한다 (D:src/storage/heap_file.c:22774-22830).
- D4. 삭제한 slot은 페이지 anchor 타입에 따라 처리한다. DONT_REUSE면 REC_MARKDELETED, ANCHORED면 REC_DELETED_WILL_REUSE다. `total_free`에 길이와 waste를 더하고, 레코드가 끝에 있었으면 `cont_free`와 `offset_to_free_area`도 조정한다 (D:src/storage/slotted_page.c:2054-2110).
- D5. 임계값 `maxslotted_dev = ALIGN_DOWN4(IO_PAGESIZE − 148)`(계산값: 16K→16236). 11.4에서 BIGONE였던 레코드도 길이가 이 값 이하면 D3에 따라 HOME으로 돌아갈 수 있다.

**E. representation 디렉터리 재생성 (클래스마다)**
- E1. 새 클래스 레코드에서 `orc_diskrep_from_record` 규칙으로 DISK_REPR를 만든다. fixed 속성 먼저, 다음 variable 순서다. 각 속성의 val_length와 value는 기본값 디스크 바이트, n_btstats는 그 속성 BTID 수다 (D:src/base/object_representation_sr.c:193-330).
- E2. BT_STATS는 120B로 쓰고 BTID는 재빌드한 인덱스 것을 넣는다. keys/pkeys/leafs/pages/height는 0, `has_function`은 함수 인덱스 첫 키일 때 1, offset 24와 reserved는 0이다. 통계는 도착 DB에서 `UPDATE STATISTICS`로 채운다.
- E3. CLS_INFO의 HFID, tot_pages, time_stamp는 출발값을 복사하고, tot_objs는 @32 INT64(부호확장)에 쓴다. @16과 40..55는 0이다. rep_dir에는 새 디렉터리 OID를 넣는다.
- E4. 디렉터리 레코드는 32B로 쓴다. item0은 CLS_INFO 위치이고 repr_id = NULL_REPRID(−1), count=2다. item1은 DISK_REPR 위치이고 repr_id = 클래스 repid(INT16)다 (D:src/storage/system_catalog.c:2109-2230; NULL_REPRID D:src/storage/storage_common.h:618).
- E5. view처럼 HFID가 NULL인 클래스는 rep_dir NULL을 허용한다. 반대로 HFID가 있으면 rep_dir은 NULL이면 안 된다 (D:src/object/transform_cl.c:3681-3686 assert).

**F. OID 재매핑 표 (클래스 레코드 안)**
- F1. 그대로 두는 것: 클래스 OID, HFID, sub/super 클래스 OID set, attribute `class_mop`(ORC_ATT_CLASS_OFFSET), domain의 class OID, FK의 `ref_class_oid`.
- F2. 바꾸는 것: rep_dir(@88), owner(@152), triggers set, properties 안의 모든 BTID 문자열(제약 BTID와 FK `pk_btid`).
- F3. 클래스 레코드가 끝나면 `tf_class_size`와 같은 결과가 나와야 한다. 각 하위구조는 `start + offset == ptr`을 만족해야 한다. 이 두 조건을 자체 검증한다 (D:src/object/transform_cl.c:3806-3809, 4534).

## 6. Open questions

1. NCHAR/VARNCHAR 칼럼이 있는 11.4 DB는 거부할지, VARCHAR로 바꿀지 정해야 한다. develop은 해당 타입 처리 경로가 없다 (bb8f3cbda). 기준 DB 범위에 NCHAR가 없으면 거부가 최소안이다.
2. `_db_user`/`_db_trigger`/`_db_serial` 행을 "신규 할당"하면 owner와 triggers OID 재매핑이 필요하다. 행 OID를 보존하는 쪽이 더 단순하다. 어느 쪽인지는 `_db_*` 재생성 티켓의 결정을 따른다.
3. auto_increment serial 이름은 develop에서 길이가 `DB_MAX_SERIAL_NAME_LENGTH`(223)를 넘으면 md5 축약 이름을 쓴다 (217ea8c44, PR #7230; D:src/object/transform.c 하단 `set_auto_increment_serial_name`). 클래스 레코드는 이름을 저장하지 않고 로드할 때 이름으로 찾는다 (D:src/object/transform_cl.c:4190-4200). 따라서 긴 이름 serial은 `_db_serial` 쪽에서 개명해야 한다. 이는 serial 담당 티켓으로 넘긴다.
4. root 힙 헤더 레코드(`HEAP_HDR_STATS`)는 bestspace 재설계로 형식이 바뀌었다 (e84a7f6dc). spage 헤더의 `need_update_best_hint` 비트도 삭제됐다 (D:src/storage/slotted_page.h:76-81). D1~D3에서 NEWHOME 페이지 선택과 ovf 파일(`ovf_vfid`) 생성이 이 헤더에 의존한다. 이는 힙/파일 관리자 티켓의 결과로 확정한다.
5. C3에서 repid 번호를 유지하는 대신 +1로 올려 옛 rep를 남기는 안도 있다. 다만 옛 rep 설명도 develop 규칙으로 다시 써야 하므로 이득이 없다. 리드 승인이 필요하다.
6. `catalog_fixup_missing_disk_representation`/`_class_info`는 정의만 있고 호출부가 없다 (rg 기준, D:src/storage/system_catalog.c:3772, 4069). 따라서 catalog을 비워 두고 엔진이 복구하게 하는 경로는 쓸 수 없다.

## 7. Sources

- 엔진 소스: develop `5b1867174` (`/home/cubrid/dev/cubrid-worktree/develop`), `origin/release/11.4` `46212adcd`; 파일 `src/object/transform_cl.c`, `src/object/transform.[ch]`, `src/base/object_representation.h`, `src/base/object_representation_constants.h`, `src/base/object_representation_sr.c`, `src/storage/system_catalog.[ch]`, `src/storage/heap_file.c`, `src/storage/slotted_page.[ch]`, `src/storage/overflow_file.h`, `src/storage/storage_common.[ch]`, `src/object/class_object.[ch]`, `src/object/schema_manager.c`, `src/object/object_primitive.c`, `src/object/object_representation.c`, `src/compat/dbtype_def.h`, `src/object/schema_system_catalog_constants.h`, `src/query/execute_schema.c`.
- 커밋/PR (CUBRID/cubrid, 모두 merged): 1f1263217 #6443 (CBRD-25862, partition·제약 시퀀스·FK match), 8ba543178 #6903 (catalog 클래스명 `_db_*`), 519cc1a43 #7856 (CBRD-27140 INT64 통계), 07aec2c5c #7957 (CBRD-27429 V0 reader 삭제), 83b29b02c #7164 + a9fca9002 #7326 (CBRD-26663/26956 CHAR 가변), de7bc5ec2 #6486 (CBRD-26006 NUMERIC 가변·scale 인코딩), bb8f3cbda #6420 (CBRD-24156 NCHAR 제거, VarNChar→String), e84a7f6dc #7353 (CBRD-26176 bestspace, maxslotted 식), 217ea8c44 #7230 (CBRD-26841 serial 이름), 5de66400a #8104 (CBRD-27324 DEDUPLICATE 삭제).
- packed domain의 scale 인코딩은 develop에서 `scale ≥ 128 || scale < 0`일 때만 확장된다. 11.4의 NUMERIC scale(≤ 38)에서는 바이트가 같다 (D:src/object/object_representation.c:2529-2541, de7bc5ec2).
