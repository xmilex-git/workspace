# R15 — 2단계 도착 11.4: 10.2·11.2·11.3 → 11.4 차이와 11.4 B-tree 레이아웃 vs develop (#527, map #472)

기준 브랜치 끝(엔진 `~/dev/cubrid-worktree/develop`, 읽기 전용):
- develop(dev) = `5b1867174`
- 10.2 = `origin/release/10.2@416bb667c`, 11.2 = `@baf1d297d`, 11.3 = `@8acbed10e`, 11.4 = `@46212adcd`
- fastmig = `~/dev/cubrid-fastmig@5a134ee` (읽기 전용). 검증기 실행은 `target/release/cubrid-fastmig`(sha256 `63b44c195eab509d…`)로 했다.

표기:
- `파일:줄@<선>`의 `<선>`은 위 브랜치 끝이다. fastmig 인용은 `crates/...:줄@5a134ee`이다.
- 구조체 오프셋은 11.4.6.1963 install의 `lib/libcubrid.so`에서 gdb `ptype /o`로 확인했다(`btree_root_header`, `btree_node_header`, `btree_overflow_header`). 증거와 검증기 출력은 `.git_ignored_dir/scratch/map472-pairs/527/`에 있다.
- 계산으로만 얻은 값에는 "(계산)"을 붙였다.
- 앞선 결정은 다시 묻지 않고 인용만 한다: R1~R7, R8(#513), R9(#510), R10(#511), P1d(#493), P1l(#503), P1n(#505).

## 1. 결론

1. **"11.4→11.4 결함 59건"은 11.4가 develop 레이아웃 B-tree를 읽은 결과가 아니다.** 그 run(#505)의 same-version 경로는 B-tree를 다시 짓지 않았다. 그래서 11.4 엔진이 만든 B-tree가 그대로 남았고, fastmig 검증기가 그 트리를 develop 도착 규칙으로 검사했다.
   - 재현: 마이그레이션하지 않은 `fm114_clean` pristine에 `verify --role target`을 돌리면 같은 59건이 나온다. 내역은 root-mvcc-fields 52, oids-not-ascending 5, ovf-oid-header 2다.
   - 같은 DB에 `--role source`를 돌리면 0건이다.
   - fm114_dirty pristine에도 같은 59건이 그대로 들어 있다(그 위에 vacuum 잔여 결함이 더 있다).
2. 59건을 항목별로 나누면 다음과 같다(§3.1).
   - **52건은 레이아웃 차이가 아니다.** 엔진이 CS 모드 `CREATE INDEX`에서 `creator_mvccid`를 현재 MVCCID로 쓴다(btree_load.c:1921-1922@11.4, :2649@dev; 실제 값 7..105). fastmig 빌드는 0을 쓴다.
   - **5건도 레이아웃 차이가 아니다.** 엔진 DML이 비유니크 리프 레코드에 OID를 정렬하지 않고 덧붙인다(`_db_auth`, `_db_stored_procedure_args`).
   - **레이아웃 차이는 2건뿐이다.** `_db_domain.i__db_domain_data_type`의 비유니크 overflow OID 페이지 헤더가 8B다. 11.4에는 CBRD-24094(#7447) 디렉터리가 없다.
3. **바이트가 같은 것(11.4 = develop):**
   - 노드 헤더 32B(`common_prefix` 포함), 루트 고정부 88B, 통계 INT64 3개
   - 리프·비리프 레코드 형식, 레코드 플래그(FENCE 0x1000, OVERFLOW_OIDS 0x2000, OVERFLOW_KEY 0x4000, CLASS_OID 0x8000)와 MVCC 플래그(INSID 0x4000, DELID 0x8000)
   - 고정 크기 객체 32/24B, 리프 레코드 객체 상한, 키 인페이지 상한 `DB_PAGESIZE/8`, unfill 임계값, 오버플로 키 파일, 비리프 prefix 도메인
   - 근거: 함수 단위 diff 0 — `btree_write_record`@11.4 대 `btree_write_record_header`/`_ex`@dev, `btree_leaf_record_handle_first_overflow`, `btree_get_prefix_separator`, `btree_generate_prefix_domain`, `btree_store_overflow_key`, `btree_pack_root_header`.
4. **11.4 B-tree가 develop과 다른 것은 넷이다.**
   - (a) 비유니크 overflow OID 페이지 헤더: 11.4는 8B만 있고 디렉터리 페이지가 없다.
   - (b) 루트 off 68: 11.4는 `rev_level:16 | deduplicate_key_idx:16`(idx+1 저장)이다.
   - (c) 루트 `packed_key_domain`: 11.4의 `or_put_domain` 형식이다. built-in 슬롯 번호, NUMERIC 기본 정밀도와 scale 경계가 다르다.
   - (d) 키 이미지: 11.4는 CHAR/NCHAR가 고정 길이(공백 패딩)이고 NUMERIC은 옛 형식이다.
   - (c)와 (d)를 틀리면 11.4가 키를 잘못 읽는다. (a)를 틀리면 11.4의 overflow 링크 수정이 실패한다. (b)는 DEDUPLICATE 인덱스에서만 문제가 된다.
5. **develop 레이아웃 B-tree를 11.4가 읽으면 생길 결함(정적 판독, §3.2).**
   - CHAR/NUMERIC 키 오독: 키 길이, 비교, MIDXKEY 오프셋이 깨진다.
   - built-in VARCHAR/CHAR 참조가 11.4에서는 VARNCHAR/NCHAR로 풀린다. develop의 `tp_Domains` 27/28번 슬롯이 그 자리에 있다(object_domain.c:327-329@dev).
   - 16B overflow 헤더를 단 페이지가 비면 `btree_modify_overflow_link`가 `S_DOESNT_FIT`으로 `assert_release`와 ER_FAILED를 낸다(btree.c:10087-10093@11.4).
   - `pgbuf_is_thread_high_priority`는 optdebug에서 assert를 낸다(btree.c:34132@11.4).
   - 디렉터리 페이지는 할당돼 있지만 어디서도 닿지 않는다. 그래서 `npages` 통계가 부풀려진다.
   - DEDUPLICATE 인덱스는 `same_prefix_len`을 잃는다.
6. **도착 11.4는 도착 develop보다 할 일이 적다.** develop 쪽 변환 가운데 다음은 모두 필요 없다(R1·R2·R3·R7·P1p).
   - HEAP_HDR_STATS 296→1152 transform, bestspace 페이지, FILE_HEADER 216→200 patch, SPAGE 비트, 로그 `sysmeta_version`
   - CHAR/NUMERIC/NCHAR 재인코딩, BT_STATS V1, 클래스 객체 4개 내용 차이, XASL opcode 재번호(11.x 출발), CBRD-23700 LOB 디렉터리 이동
7. **옛 출발 → 11.4에 남는 것(R8 표를 도착 11.4 관점으로 다시 읽은 결과).**
   - 공통(10.2·11.2·11.3): 볼륨 page 0 transform(128→136B), 로그 헤더 376B 디코더, 11.4 레이아웃 same-slot 행 매퍼(grants 3→4, serial `attr_name`, SP 재설계와 `unique_name`), 11.4 템플릿 카탈로그 재생성(11.2·11.3은 28→29 테이블, vclass 20)
   - 10.2만: LZO→LZ4 문자열 재인코딩, BOOT_DB_PARM 124→136B와 keyinfo·`_keys` 신설(R9), 클래스 객체 84B 디코더, 이름 한정(R10), 스트림 1단 재매핑(+1, FUNC +5)
   - 11.2·11.3 → 11.4 스트림은 그대로다. `OPERATOR_TYPE`과 `FUNC_CODE` 토큰 목록이 11.2 = 11.3 = 11.4다.
8. **쌍별 등급 예측(§4).**
   - 전 페이지 transform이 필요한 쌍은 없다.
   - 11.4→11.4: copy + vacuum patch + B-tree 재빌드 + catalog patch(same-version)
   - 11.2/11.3→11.4: 위에 page 0 transform, 로그 헤더 디코드, same-slot 행 transform, 카탈로그 재생성을 더한다. 사용자 힙 페이지는 **그대로**다(인코더 동일, 힙 헤더 동일).
   - 10.2→11.4: 위에 문자열 보유 클래스 레코드 transform과 boot parm transform을 더한다.
9. **fastmig에 넣을 11.4 출력 분기는 14개다(§5).** 핵심은 넷이다.
   - `ovf_oid_chain::write_overflow_oids`의 8B 헤더와 디렉터리 없음
   - `index_def::index_shape`/`key_domain`/`is_builtin_attribute_domain`의 `VersionLine::Develop` 고정 해제
   - `heap_keys`의 레코드 디코드 선
   - `build_index` 루트 off 68(DEDUP)
   - 나머지는 검증기 규칙, 카탈로그 BT_STATS V0, 11.4 클래스 객체 인코더, 템플릿이다.

## 2. 11.4 B-tree 대 develop: 바이트 표

### 2.1 노드 헤더 (리프·비리프 slot 0, host order)

| off | size | 필드 | 11.4 | develop | 커밋 / 근거 |
|---|---|---|---|---|---|
| 0 | 8 | `split_info` (pivot f32, index i32) | 같음 | 같음 | btree_load.h:195@11.4, :230@dev |
| 8/16 | 8/8 | `prev_vpid` / `next_vpid` | 같음 | 같음 | gdb 11.4.6 |
| 24/26 | 2/2 | `node_level` / `max_key_len` | 같음 | 같음 | |
| 28 | 4 | `common_prefix` | 있음 | 있음 | CBRD-25082 `c1e7266a3` #4789 (11.4 GA 포함, R8 §2.13) |
| 크기 | | | 32B (gdb) | 32B | `BTREE_IS_PAGE_VALID_LEAF`가 길이 32로 리프를 가른다 |

### 2.2 루트 헤더 (루트 slot 0, host order)

| off | size | 필드 | 11.4 | develop | 커밋 / 근거 |
|---|---|---|---|---|---|
| 0 | 32 | `node` | 같음 | 같음 | |
| 32/40/48 | 8×3 | `num_oids`/`num_nulls`/`num_keys` INT64 | 같음 (unique만 값, 그 외 −1) | 같음 | btree_load.h:207-226@11.4; 11.3까지는 int + `_64` 비트필드 (:216@11.2, :227@11.3) |
| 56 | 8 | `topclass_oid` | 같음 | 같음 | |
| 64 | 4 | `unique_pk` | 같음 | 같음 | |
| 68 | 2 | 11.4: `_32.rev_level:16` (LE 하위) / dev: `int rev_level` 하위 | 0 | 0 (`BTREE_CURRENT_REV_LEVEL`) | gdb는 `68:16`으로 표시한다(MSB 기준 표기). 첫 비트필드가 하위 16비트다 |
| 70 | 2 | 11.4: `_32.deduplicate_key_idx:16` = idx+1 (0 = 없음) / dev: `rev_level` 상위 = 0 | **DEDUP 인덱스면 ≠0** | 0 | `SET_DECOMPRESS_IDX_HEADER` btree_load.h:221@11.4. dev는 `5de66400a` #8104 (CBRD-27324)에서 삭제 |
| 72 | 8 | `ovfid` | 같음 | 같음 | |
| 80 | 8 | `creator_mvccid` | SERVER_MODE 빌드 = 현재 MVCCID, SA = NULL (btree_load.c:1921-1924@11.4) | 같음 (:2649-2651@dev) | 11.4 사용처는 `check_not_vacuumed` 끄기뿐이다 (btree.c:15820-15821@11.4) |
| 88 | 가변 | `packed_key_domain` = `or_put_domain(key_type)` | **11.4 형식** | develop 형식 | §2.6 |

### 2.3 리프 레코드, 비리프 레코드, MVCC 필드

| 영역 | 11.4 | develop | 근거 |
|---|---|---|---|
| 리프 레코드 순서 | 첫 OID(BE, slotid 상위 4비트 = 레코드 플래그, volid 상위 2비트 = MVCC 플래그) · [class OID] · [INSID] · [DELID] · 키 이미지 또는 6B 키 VPID · align4 · 추가 객체 · [8B overflow VPID] | 같음 | `btree_write_record` btree.c:4095-4222@11.4 = `btree_write_record_header`+`_ex`@dev (R6 §3.3) |
| 플래그 상수 | FENCE 0x1000, OVF_OIDS 0x2000, OVF_KEY 0x4000, CLASS_OID 0x8000; INSID 0x4000, DELID 0x8000 | 같음 | btree.c:108-123@11.4, :113-128@dev |
| 고정 크기 객체 | unique 32B, 비유니크 24B | 같음 | btree_load.h:119-121@11.4, :151-153@dev |
| 리프 레코드 객체 상한 | `(DB_PAGESIZE/8)/fixed` = 63 / 85 (계산, DB_PAGESIZE 16344) | 같음 | btree_load.h:136-142@11.4 |
| 첫 객체가 overflow를 가질 때 | 고정 크기, unique면 CLASS_OID | 같음 | `btree_leaf_record_handle_first_overflow` 함수 diff 0 |
| 비리프 레코드 | 자식 pageid i32 · volid i16 · key_len i16(−1 = overflow 키) · 키 · align4 | 같음 | `btree_write_fixed_portion_of_non_leaf_record_to_orbuf`, `_read_` diff 0 |
| 비리프 키 도메인 | key_type. BIT만 VARBIT | 같음 | `btree_generate_prefix_domain` btree.c:5938-5962@11.4 (diff 0) |
| 빌드 MVCC (all-visible) | 리프 첫 객체 플래그 0, 고정 크기 위치는 INSID=3·DELID=0 | 같음 | `bt_load_add_same_key_to_record` diff는 디렉터리 캡처뿐 |

### 2.4 overflow OID 페이지와 디렉터리

| 항목 | 11.4 | develop unique | develop 비유니크 | 커밋 / 근거 |
|---|---|---|---|---|
| slot 0 헤더 | 8B `{next_vpid}` (gdb) | 8B | **16B `{next_vpid, dir_vpid}`** | `10a1df3e6` #7447 CBRD-24094; btree_load.h:234@11.4, :262-280@dev |
| 디렉터리 페이지 | 없음 | 없음 | 체인이 데이터 페이지 2장 이상이면 생긴다. 엔트리 16B `{sep_oid, vpid}`, 페이지당 `(DB_PAGESIZE−256)/16` = 1005 (계산) | btree_load.h:289-298@dev |
| 레코드 최대 | `DB_PAGESIZE − align(SPAGE_HEADER) − align(8)` | 같음 | `− align(16)` | btree_load.h:147@11.4, :181-185@dev |
| 페이지 안 OID 순서 | 오름차순, 이진 탐색 | 같음 | 같음, 페이지 사이도 오름차순 | `btree_find_oid_from_ovfl` btree.c:12045-12152@11.4 |
| 새 overflow 페이지 위치(DML) | 체인 **머리**에 넣는다 (`next = 옛 첫 페이지`) | — | 디렉터리 규칙 | `btree_start_overflow_page` btree.c:3968-4001@11.4 |
| 빌더 헤더 | `btree_init_overflow_header` 8B (btree_load.c:615-623@11.4) | 8B | `btree_ovf_dir_init_header` 16B (btree_load.c:3546, :3727@dev) | |
| 페이지 종류 판별 | 헤더 길이 8 = OVF, 32 = 노드, 그 밖 = 루트 (`btree_get_perf_btree_page_type` btree.c:34090-34137@11.4) | — | 길이 < 16이면 레거시 (`btree_ovf_dir_get_header` btree_load.c:1095@dev) | |

### 2.5 임계값과 상한

| 상수 | 11.4 | develop | 근거 |
|---|---|---|---|
| `LOAD_FIXED_EMPTY_FOR_LEAF` | `DB_PAGESIZE × unfill + 6` = 823.2 (계산) | 같음 | btree_load.h:56-58@11.4, :88-90@dev |
| `LOAD_FIXED_EMPTY_FOR_NONLEAF` | `DB_PAGESIZE × max(unfill, 0.1) + 6` = 1640.4 (계산) | 같음 | :59-61@11.4, :91-93@dev |
| `bt_unfill_factor` 기본 | 0.05 | 0.05 | system_parameter.c:981@11.4 |
| `BTREE_MAX_KEYLEN_INPAGE` / `BTREE_MAX_OIDLEN_INPAGE` | `DB_PAGESIZE/8` = 2043 (계산) | 같음 | btree_load.h:136-138@11.4, :168-170@dev |
| 키 길이 판정 기준 | **11.4 키 이미지 길이**(CHAR(n)은 패딩 포함 `STR_SIZE`) | develop 이미지 길이 | §2.7 |

### 2.6 루트 `packed_key_domain` (키 도메인 표기)

| 항목 | 11.4 | develop | 근거 |
|---|---|---|---|
| built-in 참조의 슬롯 번호 (`built_in_index = i+1`, 같은 도메인이 여러 슬롯에 있으면 마지막 것) | VARCHAR 5, CHAR 26, NCHAR 27, VARNCHAR 28 | VARCHAR **28**, CHAR **27** (`#define tp_NChar_domain tp_Char_domain`, `tp_VarNChar_domain tp_String_domain`) | object_domain.c:327-329, :676@dev; fastmig `packed_domain.rs:50-73@5a134ee` |
| built-in NUMERIC | (15, 0) | (40, 0) | fastmig `domain.rs:22-24` |
| NUMERIC floating precision 표기 | 38 | 40 | `packed_domain.rs:259-263` |
| NUMERIC scale를 carrier에 바로 쓰는 상한 | < 255 | < 128 | `packed_domain.rs:247-252`, `de7bc5ec2` #6486 |
| NCHAR/VARNCHAR | 타입 있음, collation 워드 있음 | 타입 없음 (CHAR/VARCHAR 별칭) | `bb8f3cbda` #6420 CBRD-24156 |
| explicit 대 built-in | 11.4 엔진은 `db_user.u_db_user_name`과 `db_serial.pk_db_serial_unique_name` VARCHAR 키를 explicit으로 쓴다 | fastmig 규칙은 built-in 참조로 쓴다(풀면 같은 도메인) | P1l #503 코멘트 (11.4 67/69) |
| DEDUPLICATE 숨은 열 | MIDXKEY 끝(함수 열 앞)에 SHORT 원소 | 없음 | deduplicate_key.c:30-40, :121-138@11.4 |

### 2.7 키 이미지 (원소 인코딩)

| 타입 | 11.4 | develop | 근거 |
|---|---|---|---|
| CHAR(n) / NCHAR(n) | `STR_SIZE` 바이트 고정, 공백 패딩. 정밀도가 없으면 LE i32 길이 + 바이트 | CHAR: `[len<255]` 또는 `[0xFF][BE clen][BE len]` 가변, 압축 가능. NCHAR 없음 | `83b29b02c` #7164, `a9fca9002` #7326; fastmig `index_image.rs:1-20, 320-321` |
| NUMERIC | 11.4 데이터 형식 (fastmig `write_numeric_11_4`) | 헤더 가변 형식 | `de7bc5ec2` #6486; `index_image.rs:417-418, 507-508` |
| VARCHAR, 정수·날짜·OID 등 | 같음 | 같음 | R2, P1b #491 |
| MIDXKEY 헤더 | nullmap + 1B 오프셋 표 (255 = 범위 밖) | 같음. 다만 CHAR가 가변이라 원소 오프셋 값이 다르다 | object_representation.h:2822-2961@11.4 (R6 §3.7) |
| DEDUP 숨은 원소 값 | `pageid % 2^level` SHORT (`level` = `0x8A8B8C90 − attr_id`) | 없음 | `dk_get_deduplicate_key_value` deduplicate_key.c:142-168@11.4, `CALC_MOD_VALUE_FROM_LEVEL` :45 |

## 3. 11.4→11.4 결함 59건과, 11.4가 develop 레이아웃 B-tree를 읽는 경우

### 3.1 59건의 실제 내역 (재현)

```
cubrid-fastmig verify /home/cubrid/fastmig-basedb/11.4/pristine/clean/fm114_clean --role target   → 종료 1, 59건 (target.2)
cubrid-fastmig verify …/fm114_clean --role source                                                  → 종료 0, 0건
cubrid-fastmig verify /home/cubrid/fastmig-basedb/11.4/pristine/dirty/fm114_dirty --role target   → 같은 59건 + vacuum 잔여 결함
```

| 결함 코드 | 건수 | 대상 | 검사 규칙 (fastmig) | 원인 | 11.4 레이아웃 차이인가 |
|---|---|---|---|---|---|
| `root-mvcc-fields` | 52 | 엔진이 만든 사용자·카탈로그 인덱스 루트. actual은 전부 `off68 = 0x0`, `creator_mvccid` 7..105 | `off68 != 0 \|\| creator_mvccid != 0`이면 결함 (`verify/src/btree_walk.rs:142-151@5a134ee`) | 엔진 CS `CREATE INDEX`가 `logtb_get_current_mvccid`를 쓴다 (btree_load.c:1921-1922@11.4, btree.c:5831-5832@11.4). develop CS도 같다 (btree_load.c:2649@dev) | **아니다.** 빌더 불변식이다. 11.4도 0(NULL)을 정상으로 읽는다(`MVCCID_IS_VALID` 검사, btree.c:15820@11.4) |
| `oids-not-ascending` | 5 | `_db_auth.i__db_auth_grantee`, `i__db_auth_object_of`, `_db_stored_procedure_args.i__…_sp_of`(3) | 비유니크 리프 레코드 안 OID가 오름차순이 아니면 결함 (`btree_walk.rs:510-512`) | 엔진 insert는 리프 레코드 끝에 OID를 덧붙인다. develop 엔진도 같다(#484 (A2): develop `i__db_domain_data_type` 10건) | **아니다.** 빌더 불변식이다 |
| `ovf-oid-header` | 2 | `_db_domain.i__db_domain_data_type`, overflow 페이지 0\|1603, 0\|1602 | 비유니크인데 헤더가 16B가 아니면 결함 (`btree_walk.rs:628-633`) | 11.4에 CBRD-24094 디렉터리가 없어 8B 헤더다 | **그렇다** (§2.4). 도착 11.4라면 8B가 정답이다 |

정리:
- #505의 same-version run은 B-tree를 다시 짓기 전(`4645a89`)에 돌았다. 그래서 출발 B-tree가 AsIs로 남았다.
- 59건은 "11.4 엔진이 만든 트리 + develop 도착 규칙"의 결과다. 11.4가 develop 레이아웃을 읽어서 생긴 결함이 아니다.
- 현재 same-version 경로는 B-tree를 전부 다시 짓는다(ADR 0005, P1m #504). 따라서 11.4 도착에서 남는 문제는 빌더와 검증기가 develop 규칙만 안다는 점이다.

### 3.2 develop 레이아웃 B-tree를 11.4가 읽으면 (빌더를 고치지 않고 도착 11.4로 쓸 때, 정적 판독)

| # | 차이 | 11.4에서 일어나는 일 | 심각도 | 근거 |
|---|---|---|---|---|
| L1 | 키 이미지 CHAR/NCHAR 가변 vs 고정 | 11.4 `index_readval`/`index_cmpdisk`는 `STR_SIZE` 고정 바이트를 읽는다. 키 경계, 레코드 안 OID 위치, MIDXKEY 오프셋이 어긋난다. 검색이 틀리거나 서버가 죽는다 | 치명 | §2.7 |
| L2 | 키 이미지 NUMERIC | 11.4 NUMERIC reader가 develop 헤더 형식을 오독한다. 값과 순서가 틀린다 | 치명 | §2.7 |
| L3 | 키 도메인 built-in 슬롯 | develop 규칙의 built-in VARCHAR 참조(28)를 11.4가 `tp_VarNChar_domain`으로 푼다. CHAR(27)는 NCHAR가 된다. 키 타입·codeset·collation이 바뀌어 비교와 플랜 도메인 검사가 어긋난다. 해당 인덱스(T1: `db_user.u_db_user_name`, `db_serial.pk_db_serial_unique_name` 같은 VARCHAR built-in)가 영향을 받는다 | 치명 | §2.6 |
| L4 | 키 도메인 NUMERIC 정밀도·scale | built-in NUMERIC이 11.4에서는 (15,0)이 된다. floating 40은 11.4 최대 38을 넘는다 | 높음 | §2.6 |
| L5 | overflow 헤더 16B (비유니크) | 읽기와 순회는 된다(`next_vpid`가 +0). 그러나 다음 셋이 문제다. (i) 중간 overflow 페이지가 비어 해제될 때 앞 페이지 링크를 고치는 `btree_modify_overflow_link`가 `area_size = 8`로 `spage_get_record(COPY)`를 부른다. 결과는 `S_DOESNT_FIT` → `assert_release(false)`, ER_FAILED다(btree.c:10087-10093, 호출 :32463@11.4). 그래서 DELETE와 vacuum이 실패한다. (ii) optdebug `pgbuf_is_thread_high_priority`(page_buffer.c:10859, 10889@11.4)가 부르는 `btree_get_perf_btree_page_type`이 길이 16을 루트로 보고 `assert (length >= 88)`에 걸린다(btree.c:34132@11.4). (iii) 11.4가 새 overflow 페이지를 8B로 체인 머리에 넣어 혼합 체인이 된다(동작은 함) | 높음 (DML 실패) | §2.4 |
| L6 | 디렉터리 페이지 | 11.4 어떤 경로도 이 페이지에 닿지 않는다. B-tree 파일에 할당된 고아 페이지가 되고, `file_get_num_user_pages` 기반 통계(btree.c:7419, 7552@11.4)가 부풀려진다 | 낮음 | §2.4 |
| L7 | 루트 off 70 = 0 (DEDUP 인덱스) | 11.4가 `deduplicate_key_idx = −1`로 읽는다(btree.c:6008-6009@11.4). 스캔과 통계의 `same_prefix_len`(:7507, :9188)이 틀린다. 키에는 여전히 숨은 열이 있어야 하므로, 열을 빼고 지은 develop 방식의 키는 11.4 DML이 만드는 키와 모양이 다르다 | 높음 (DEDUP 인덱스만) | §2.2, §2.6 |
| L8 | 키 인페이지 판정 | develop 이미지 길이로 overflow 키를 정하면, 11.4 고정 CHAR 이미지가 2043B 이상인데도 인라인이 될 수 있다. 그러면 11.4가 만들지 않을 레코드가 생긴다(읽기는 될 수 있음, [VERIFY]) | 중간 | §2.5 |
| — | `creator_mvccid` 0, `rev_level` 0, 노드 헤더, 레코드 형식, 플래그, 임계값 | 차이 없음 | — | §2.1~2.5 |

## 4. 출발 10.2·11.2·11.3·11.4 → 도착 11.4 (R8·R9·R10 다시 읽기)

열 머리: **10.2→11.4 | 11.2→11.4 | 11.3→11.4 | 11.4→11.4**. "= 11.4"는 출발 바이트가 11.4와 같다는 뜻이다(R8 표 근거).

### 4.1 영역별 값과 해야 할 일

| 영역 | 10.2 | 11.2 | 11.3 | 11.4 (도착) | 해야 할 일 / 커밋 |
|---|---|---|---|---|---|
| 디스크 호환 레벨 | 10.15f | 11.2f | 11.2f | 11.4f | 새 로그 헤더에 11.4f를 쓴다. 11.2/11.3은 `db_release`로 가른다 (R8 §1.8) |
| FILEIO 예약 32B | `pflag`·nonce 자리 0 | = 11.4 | = 11.4 | 기준 | 그대로 (R9 §1.3) |
| 볼륨 헤더 | 128B | 128B | 128B | 136B (`vol_creation` @80) | ≤11.3: page 0 transform. 11.4: patch(경로·LSA) — `44c022c31` #5719 |
| 로그 헤더 | 376B | 376B | 376B | 384B, +102 `dummy3/4` (develop `sysmeta_version` 아님) | 새로 쓴다. 출발 헤더는 376B 디코더 (R8 §2.14) |
| `BOOT_DB_PARM` | 124B | 136B | 136B | 136B | 10.2: transform, keyinfo 힙과 `_keys` 생성 (R9 §1.5; 11.4 부팅 동작은 [VERIFY]) |
| `FILE_HEADER` | 216B | 216B | 216B | **216B** | 그대로 (develop 도착의 184..199 patch가 필요 없다) |
| `HEAP_HDR_STATS` | 296B | 296B | 296B | **296B** | 그대로. bestspace 페이지를 만들지 않는다. vacuum 잔여 patch만 한다 |
| `HEAP_CHAIN`, SPAGE, 슬롯 | = 11.4 | = 11.4 | = 11.4 | 기준 | 그대로. `need_update_best_hint` 비트도 11.4가 쓰므로 둔다 |
| OR 레코드·MVCC 헤더, `PR_TYPE` | = 11.4 | = 11.4 | = 11.4 | 기준 | vacuum patch 규칙(R2)은 버전과 무관하다 |
| 값 인코딩 | LZO1X 압축 문자열(≥255B VARCHAR/VARNCHAR) | = 11.4 | = 11.4 | CHAR 고정, NUMERIC 옛 형식, NCHAR 유지, LZ4 | 10.2: 문자열 보유 클래스 레코드를 LZ4(또는 비압축)로 transform — `ecaa13201` #2391. 11.x: **재인코딩 없음** |
| 클래스 객체 | 고정 84B, 이름 `name` | 88B, `owner.name` | 88B + DEDUP 의사 속성 | 88B (DEDUP 유지) | 10.2: 84B 디코드 + 이름 한정(R10) → 11.4 인코더. 11.2/11.3: 11.4와 같은 형식, BTID·rep_dir 재매핑만. 11.4: same-version 재매핑 |
| catalog 파일 (DISK_REPR/ATTR/BT_STATS) | DISK_ATTR 80B | 80B | 80B | DISK_ATTR 88B(ndv), BT_STATS **V0 80B**(int keys), CLS_INFO `tot_objs` @16 int | 11.4 형식으로 재생성 — `e05227521` #4768. develop V1(120B)을 쓰면 안 된다 (R3 §1.4) |
| `_db_*`/`db_*` 테이블 | 25 | 28 | 28 | 29 (+`_db_stored_procedure_code`) | 11.4×charset 카탈로그 템플릿(ADR 0011)으로 재생성. 이름은 11.4 그대로(`db_user`, `db_serial` 등 — develop의 `_db_*` 개명 `8ba543178` #6903 이전) |
| 시스템 vclass | 18 | 20 | 20 | 20 | 11.4 템플릿 |
| same-slot 행 `db_authorization.grants` | 3-튜플 | 3-튜플 | 3-튜플 | 4-튜플 `{type, class, grantor, cache}` | ≤11.3: 앞에 `type = 0` 추가 — `1ea4a86e0` #5438 |
| `db_serial` | `att_name`, `unique_name` 없음 | + `unique_name` | 같음 | `attr_name` | ≤11.3: 칼럼 이름 변경. 10.2: `unique_name = lower(owner).name` — `b85c07b27` #5346, `14742376f` #3488 |
| `db_trigger` | `unique_name` 없음 | 있음 | 있음 | 있음 | 10.2: 생성 (R10 §2.2) |
| `_db_stored_procedure`/`_args`/`_code` | 옛 칼럼 | 옛 칼럼 | 옛 칼럼 | 재설계 + `unique_name`(PK) | ≤11.3: 행 재구성, `sp_of` OID, `unique_name` (R10 §1.10: 11.2·11.3에도 필요) |
| `_db_synonym`, `_db_server` | 없음 | 있음 | 있음 | 있음 | 10.2: 빈 테이블 |
| 이름 규칙(user schema) | 없음 | 있음 | 있음 | 있음 | 10.2: R10 전체(클래스·serial·trigger·SP 이름, 뷰·trigger·pexpr 텍스트). 길이 상한 222B도 11.4에 있다 (parser_support.c:10836@11.4) |
| 영속 XASL 스트림 | `OPERATOR_TYPE` 198 | 199 | 199 | 199 | 10.2: opcode ≥113 → +1, `FUNC_CODE` ≥`F_BENCHMARK` → +5, LZO 상수 재인코딩 (R8 §2.12). 11.2/11.3: **그대로**(enum 토큰 목록 11.2 = 11.3 = 11.4, storage_common.h@11.2/11.3/11.4, db_function.hpp@11.4). R7의 develop 재번호·VARCHAR 컨테이너는 필요 없다 |
| B-tree | 옛 루트(int 통계) | `_64` 비트필드 | + DEDUP | §2 | 전부 11.4 레이아웃으로 재빌드한다. 11.3 DEDUP 인덱스는 숨은 열을 유지한다(11.4는 기능이 있다) |
| LOB | 로케이터 형식 같음 | 같음 | 같음 | 11.4 형식(속성별 디렉터리 없음) | 참조 파일만 복사(G6). base 아래 절대 로케이터는 상대로 바꾼다. CBRD-23700 이동(P1p)은 하지 않는다 |
| TDE | 없음 | 11.4와 같은 형식 | 같음 | 기준 | 11.x: `_keys` 복사 + keyinfo 유지, 암호문 as-is (R9 §1.9). 10.2: 키 자산 생성 |
| 문자열 비교 의미 | 옛 뒤 공백 규칙 (CBRD-23731, CBRD-24149) | 11.2 줄 규칙 | 같음 | 11.4 규칙 | 재빌드는 11.4 규칙으로 정렬한다. 유니크 중복 위험은 R8 Q5와 같다 |

### 4.2 쌍별 page treatment grade 예측

복사 방식(clone/copy)은 볼륨마다 정한다. 아래는 그 뒤 제자리에서 하는 처리의 등급이다. 비교용으로 R8의 develop 도착 열을 붙였다.

| 영역 | 10.2→11.4 | 11.2→11.4 | 11.3→11.4 | 11.4→11.4 | (참고) 11.4→dev |
|---|---|---|---|---|---|
| 데이터 볼륨 일반 페이지 | as-is | as-is (TDE as-is) | as-is | as-is | as-is |
| 볼륨 헤더 page 0 | transform | transform | transform | patch | patch |
| 섹터·파일 테이블·트래커 | as-is (할당 시 patch) | 같음 | 같음 | 같음 | 같음 |
| 파일 헤더 page | **as-is** | as-is | as-is | as-is | patch |
| boot 힙 | transform + keyinfo 신설 | patch | patch | patch | patch |
| 힙 헤더 page | **as-is** (vacuum 잔여 시 patch) | 같음 | 같음 | 같음 | transform |
| 힙 데이터 page | patch/as-is + **LZO 문자열 클래스 transform** | patch/as-is | patch/as-is | patch/as-is | patch/as-is + CHAR/NUMERIC 클래스 transform |
| 오버플로 page | as-is, LZO 클래스 transform | as-is | as-is | as-is | as-is / 재인코딩 transform |
| root 힙 클래스 객체 | 재직렬화(11.4 인코더) | patch(BTID·rep_dir) | patch | patch | 재직렬화(develop) |
| same-slot 행 | transform | transform (grants, serial, SP) | 같음 | as-is | transform (R4) |
| derived 카탈로그·catalog 파일·vclass | 재생성(11.4 템플릿) | 재생성 | 재생성 | catalog 파일 재생성, `_db_index` 등 patch(이연 인덱스, BTID) | 재생성 |
| 파티션 식 스트림 | transform (1단 재매핑 + LZO) | as-is | as-is | as-is | transform (R7) |
| B-tree | 재빌드(11.4) | 재빌드(11.4) | 재빌드(11.4, DEDUP 유지) | 재빌드(11.4) | 재빌드(develop) |
| 로그 | 새로(384B 11.4) | 같음 | 같음 | 같음 | 새로(develop) |
| DWB | 옮기지 않음 | 같음 | 같음 | 같음 | 같음 |

판정:
- **11.4→11.4** 는 develop→develop(P1k #501, P1m #504)의 11.4판이다. 사용자 힙을 바꾸는 것은 vacuum 잔여 patch뿐이고, 나머지는 B-tree 재빌드, 이연 인덱스 행 제거, BTID 교체, catalog 파일 재생성이다. 필요한 새 코드는 §5의 11.4 출력 분기다.
- **11.2/11.3→11.4** 는 사용자 데이터 페이지를 하나도 transform하지 않는다. 바뀌는 것은 볼륨당 page 0 한 장과 시스템 행뿐이다. 그래서 clone 이점이 가장 크다.
- **10.2→11.4** 는 develop 도착에서 CHAR/NUMERIC 재인코딩만 빠지고 LZO 재인코딩은 그대로 남는다. 문자열이 많은 DB에서 clone 이점이 줄어드는 점은 R8과 같다.

## 5. fastmig에 넣을 11.4 출력 분기 (file:function)

현재 빌더와 카탈로그 writer는 develop 출력만 안다. plan은 `--target-version 11.4`를 거부한다 (`crates/plan/src/version_pair.rs:22-26@5a134ee`).

| # | 위치 (@5a134ee) | 지금 | 11.4 도착에서 할 일 | 막는 결함 |
|---|---|---|---|---|
| B1 | `crates/index/src/ovf_oid_chain.rs` `objects_per_page`(:18), `write_overflow_oids`(:25) | 16B 헤더(`dir: Some(..)` :49), 데이터 2장 이상이면 디렉터리 페이지(:78) | 도착 선을 인자로 받는다. 11.4면 `OvfHeader { dir: None }`(8B, 기존 `LEGACY_SIZE`)을 쓰고 디렉터리 페이지를 만들지 않는다. 용량은 8B 헤더 뒤 `max_space_for_new_record / 24`로 계산한다(16B보다 최대 1개 많다, 계산) | L5, L6, `ovf-oid-header` |
| B2 | `crates/index/src/index_def.rs` `index_shape`(:47) | `KeyDomain::new(VersionLine::Develop, ..)`(:64), `encode_packed_domain(VersionLine::Develop, ..)`(:66) | 도착 선으로 바꾼다. built-in 슬롯(VARCHAR 5 대 28), NUMERIC 38/15, scale 255, NCHAR collation 워드를 11.4 규칙으로 쓴다 | L3, L4 |
| B3 | 같은 파일 `key_domain`(:90), `is_builtin_attribute_domain`(:141) | `schema_domain(VersionLine::Develop, ..)`, `Domain::builtin(VersionLine::Develop, ..)` | 11.4 클래스 객체 도메인을 쓴다(CHAR/NCHAR 고정, NUMERIC 11.4). DEDUP 제약이면 숨은 SHORT 열을 `dk_get_deduplicate_key_position` 위치에 넣는다. built-in 판정은 11.4 엔진과 바이트가 같도록 explicit 규칙을 맞출지 정한다(남은 질문 2) | L1, L2, L7 |
| B4 | `crates/index/src/heap_keys.rs` `RecordLayout::for_repid(VersionLine::Develop, ..)`(:49), `decode_record(VersionLine::Develop, ..)`(:117) | 힙 레코드를 develop 레이아웃으로 디코드한다 | 도착 11.4 힙은 11.4 레이아웃이므로 `VersionLine::V11_4`로 디코드한다. DEDUP 숨은 값 `pageid % 2^level`을 키 끝 원소로 만든다 | L1, L2, L7 |
| B5 | `crates/index/src/build.rs` `build_index`(:96), 루트 헤더 `off68: 0`(:236) | 0 고정 | 11.4 DEDUP 인덱스면 `(idx+1) << 16`. 그 밖에는 0. `creator_mvccid`는 0 그대로 | L7 |
| B6 | `crates/index/src/rebuild.rs` `rebuild_indexes`, `class_properties(.., VersionLine::Develop)`(:71) | develop 클래스 객체 속성 | 11.4 클래스 객체를 읽는다. `SpaceManager`를 도착 선으로 만들어 새 B-tree·overflow 키 파일 헤더를 216B로 쓴다(`file_header.rs` `write(.., line)`, `file_alloc.rs:65` `SpaceManager::new(.., line, ..)`) | 11.4 파일 헤더 오독 |
| B7 | `crates/index/src/leaf_builder.rs:103`, `nonleaf_builder.rs:47` (`max_keylen_inpage`) | 이미지 길이로 판정 | 코드는 그대로 둔다. 다만 이미지를 **11.4 인코더**(`index_image::encode_image(V11_4, ..)`)로 만들어야 판정이 11.4와 같아진다 | L8 |
| B8 | `crates/ondisk/src/value/radix_words.rs` `KeyDomain::radix_words`(:218-222) | 11.4 키는 단어를 내지 않는다(compare 정렬로 떨어짐) | 정확성 문제는 아니다. 11.4 CHAR 고정(패딩 무시 콜레이션)과 NUMERIC 11.4 단어를 넣을지는 성능 판단으로 정한다 | 성능 |
| B9 | `crates/index/src/bt_stats.rs`, `crates/ondisk/src/catalog_dir/disk_repr.rs` `encode_develop`(:186), `write_bt_stats_develop`(:292), `cls_info.rs` `encode_develop`(:46) | develop V1 (BT_STATS 120B, CLS_INFO INT64 @32) | 11.4 V0 인코더: BT_STATS 80B(int keys, pkeys int×8), CLS_INFO `tot_objs` @16, DISK_ATTR 88B | 11.4 catalog 오독 |
| B10 | `crates/ondisk/src/class_object/encode.rs` `encode_develop`(:271); 호출처 `crates/catalog/src/same_version_catalog.rs:35`(`LINE = Develop`), `:281`, `catalog_write.rs:69, 166` | develop 클래스 객체만 쓴다 | 11.4 클래스 객체 인코더(partition 4B, 제약 꼬리 `{.., status, comment}`, FK 4원소, CHAR 필터 스트림, 11.4 값 인코딩; R3 §1.2의 역). same-version 11.4 경로와 옛 출발→11.4 경로가 공유한다 | 11.4 스키마 오독 |
| B11 | `crates/ondisk/src/heap_rewrite/rewrite_heap.rs` `rewrite_heap`(:65, "develop layout out" :64, 헤더 크기 차 :90) | 출력은 develop 헤더(1152B + bestspace)다 | 도착 11.4면 296B 헤더를 유지하고 vacuum 잔여만 지운다(P1k의 같은 버전 경로를 11.4 헤더로) | 11.4 힙 헤더 오독 |
| B12 | `crates/verify/src/btree_walk.rs` `walk_upper`(:141-151), `objects_of`(:591, :628-633), `KeyDomain::from_packed(db.line, ..)`(:79) | target 규칙이 develop 기준이다(off68 = 0, 비유니크 16B) | 도착 11.4면 off68 하위 16비트만 0을 요구하고 상위는 DEDUP 여부와 맞춘다. 비유니크 overflow 헤더 8B를 기대하고 디렉터리 검사를 끈다. 키 도메인과 이미지는 11.4로 연다 | 59건 중 `ovf-oid-header` 2건이 11.4 도착에서는 정상 |
| B13 | `crates/catalog/src/template_store.rs` `builtin(line, charset)` | develop×charset 템플릿 3종 | 11.4×charset 템플릿(11.4.6 엔진 산출물, ADR 0011) | 11.4 시스템 클래스 |
| B14 | `crates/plan/src/version_pair.rs` `refusal`(:21-34) | `(_, V11_4)` 거부 | B1~B13 뒤에 (10.2/11.2/11.3/11.4 → 11.4)를 허용한다. 옛 출발은 R8 D1~D11 디코더가 먼저 있어야 한다 | — |

필요 없는 것:
- 11.4 B-tree 디코더(출발 B-tree는 읽지 않는다)
- 노드·루트 고정부·리프·비리프 레코드 코덱의 변형(`ondisk::btree::{node_header, root_header, leaf_record, nonleaf_record}`는 두 선에서 그대로 쓴다)
- overflow 키 파일 변형

## 6. 남은 질문

### 티켓으로 만들 수 있는 질문

1. **[task] 11.4 레이아웃 B-tree 출력(B1~B7, B12).**
   - 수용 기준(기계적):
     - T1 `fm114_clean`·`fm114_dirty`를 11.4→11.4 rebuild한 도착이 11.4 규칙 `verify --role target` 결함 0이다.
     - 재빌드한 루트 `packed_key_domain`이 11.4 엔진 루트와 바이트가 같다(75개 중 explicit/built-in 2건은 질문 2의 결정을 따른다).
     - 11.4.6 release·optdebug SA/CS가 부팅한다.
     - 키 범위 스캔이 `;plan simple`에서 `INDEX SCAN`이고, 출발과 결과 집합이 같다.
     - 비유니크 overflow 체인 중간 페이지를 비우는 DELETE와 vacuum에서 오류와 assert가 0이다(L5 경로, fail-before는 develop 레이아웃 빌더로 확인한다).
   - 작은 DB에서 `cubrid checkdb`로 11.4 엔진의 트리 판정도 함께 본다(인덱스 구조 작업 예외).
2. **[decision] 11.4 키 도메인의 explicit 대 built-in 표기.**
   - 11.4 엔진은 `db_user.u_db_user_name`, `db_serial.pk_db_serial_unique_name`을 explicit으로 쓴다(P1l). 두 가지 중 하나를 고른다.
     - (a) 11.4 엔진과 바이트까지 맞춘다.
     - (b) 풀었을 때 같은 도메인이면 된다고 본다.
   - (b)를 고르면 11.4 `tp_domain_cache`가 같은 포인터를 돌려주는지(`btid_int.key_type` 동일성 비교 경로)를 [VERIFY]로 확인한다.
3. **[research] 11.3/11.4 DEDUPLICATE 인덱스의 실재와 재빌드 규칙.**
   - 11.4·11.3 기본값은 꺼짐이다(`DEDUPLICATE_KEY_LEVEL_SYSPARAM_DFLT = −1`, deduplicate_key.h:43@11.3/11.4). 명시 `WITH DEDUPLICATE=n` 인덱스가 실제 DB에 있는지 T4(#512) 기준 DB로 확인한다.
   - 있으면 다음 셋이 11.4 엔진이 지은 트리와 바이트가 같은지 대조한다: 숨은 열 값 `pageid % 2^level`, 위치 규칙(`dk_get_deduplicate_key_position`), 루트 off 70.
   - 함수 인덱스와 겹칠 때(`func_attr_index_start` 분기)는 이연 인덱스 규칙(#486)과 맞춘다.
4. **[task] 11.4 카탈로그 writer(B9~B11, B13).**
   - 내용: 11.4 클래스 객체 인코더, catalog 파일 V0, 11.4 템플릿, 힙 헤더 296B 유지 patch.
   - 수용 기준: T1 11.4 same-version 도착의 unloaddb 스키마 차이가 이연 인덱스뿐이고, 11.4.6 SA·CS(optdebug)에서 부팅·DML·재부팅 assert가 0이다.
5. **[task] ≤11.3 → 11.4 same-slot 행 매퍼.**
   - R8 D8(develop 도착)과 규칙을 공유하되 출력은 11.4 레이아웃이다. 클래스 이름은 `db_*` 그대로이고, 11.4 CHAR/NUMERIC 인코딩을 쓴다.
   - 정답 출처는 R8 질문 2(11.4 공식 경로가 grants `type`·SP `target` 분리·`sp_of`를 채우는 방식)와 같다. 두 도착이 한 매핑 표를 쓰도록 묶는다.
6. **[research] 10.2→11.4에서 keyinfo 없는 DB를 11.4가 여는가.**
   - R9는 develop release가 `ER_TDE_CIPHER_LOAD_FAIL`만 남기고 부팅한다고 봤다. 11.4.6에서 같은지(`boot_sr.c`@11.4)와, optdebug `tde_get_keyinfo` assert가 있는지 확인한다.

### 아직 흐릿한 것

- 11.4 도착에서 힙 헤더를 그대로 두면 vacuum patch 뒤 `HEAP_HDR_STATS`의 추정치(`estimates.num_recs`, best 힌트)가 실제와 달라진다. 11.4 엔진이 이것을 스스로 고치는지, 도구가 다시 세어야 하는지 모른다.
- 11.4 엔진이 fastmig로 채운 리프(unfill 0.05)를 무거운 DML로 쪼갤 때 develop과 다른 문제가 있는지 모른다. 레이아웃은 같지만 11.4 split 경로는 실행으로 확인한 적이 없다.
- 10.2 출발의 문자열 비교 규칙 차이가 11.4 유니크 재빌드에서 중복을 만들 수 있다(R8 Q5와 같다). 도착 11.4와 develop의 비교 규칙이 같은지도 아직 대조하지 않았다.
- clone 대 copy 선택 기준: 11.2/11.3→11.4는 사용자 페이지를 거의 쓰지 않으므로 clone이 유리하다고 예측한다. 측정은 없다.
- §3.2의 L5(ii)·L8은 정적 판독이다. 11.4 서버에 develop 레이아웃 트리를 실제로 올려 본 실행 증거는 없다. 빌더를 고치면 의미가 없어지므로, fail-before 증거로만 쓸지 정해야 한다.

## 7. Sources

- 엔진 B-tree:
  - `src/storage/btree_load.h:136-151, 195-236@11.4`, `:83-93, 151-185, 230-298@dev`
  - `src/storage/btree_load.c:370-395, 615-623, 1912-1925, 2070, 2747-2776@11.4`, `:1095, 2649-2651, 3519-3546, 3668-3727, 4461-4703@dev`
  - `src/storage/btree.c:108-123, 3968-4001, 4095-4222, 5822-5836, 5938-5962, 6008-6009, 7419, 7507, 7552, 9188, 10062-10101, 12045-12152, 12337-12394, 15812-15826, 32395-32470, 34090-34137@11.4`
  - `src/storage/page_buffer.c:10859-10895, 13833-13836@11.4`
  - 함수 단위 diff(11.4 대 dev): `bt_load_add_same_key_to_record`, `bt_load_nospace_for_new_oid`, `bt_load_make_new_record_on_leaf_page`, `btree_pack_root_header`, `btree_init_root_header`, `btree_glean_root_header_info`, `btree_get_prefix_separator`, `btree_generate_prefix_domain`, `btree_store_overflow_key`, `btree_load_overflow_key`, `btree_leaf_record_change_overflow_link`, `btree_leaf_record_handle_first_overflow`, `btree_get_next_overflow_vpid`, `btree_write_fixed_portion_of_non_leaf_record_to_orbuf`
  - gdb `ptype /o` `/home/cubrid/release/CUBRID-11.4.6.1963/lib/libcubrid.so`
- DEDUPLICATE: `src/object/deduplicate_key.h:36-76@11.3/11.4`, `src/object/deduplicate_key.c:30-40, 45, 121-168@11.4`. 커밋 `7add5356d` #4401 (CBRD-24478), `5de66400a` #8104 (CBRD-27324).
- 도메인: `src/object/object_domain.c:327-329, 676@dev`; fastmig `crates/ondisk/src/value/{packed_domain,domain,index_image,radix_words,key_domain}.rs@5a134ee`.
- 커밋: `10a1df3e6` #7447 (CBRD-24094), `c1e7266a3` #4789 (CBRD-25082), `44c022c31` #5719, `1ea4a86e0` #5438, `b85c07b27` #5346, `14742376f` #3488, `e05227521` #4768, `ecaa13201` #2391, `0cf60dd26` (CBRD-23608), `83b29b02c` #7164, `a9fca9002` #7326, `de7bc5ec2` #6486, `bb8f3cbda` #6420, `8ba543178` #6903.
- 스트림 enum: `src/storage/storage_common.h@11.2/11.3/11.4` (`OPERATOR_TYPE` 블록 해시 동일), `src/compat/db_function.hpp@11.4` 대 `storage_common.h@11.2` (`FUNC_CODE` 토큰 77개 동일).
- 이름 길이: `src/parser/parser_support.c:10836@11.4`.
- fastmig: `crates/index/src/{ovf_oid_chain,index_def,heap_keys,build,rebuild,leaf_builder,nonleaf_builder,bt_stats,index_shape,btree_file}.rs`, `crates/ondisk/src/btree/*.rs`, `crates/ondisk/src/{file_header,file_alloc}.rs`, `crates/ondisk/src/catalog_dir/{disk_repr,cls_info}.rs`, `crates/ondisk/src/class_object/encode.rs`, `crates/ondisk/src/heap_rewrite/rewrite_heap.rs`, `crates/catalog/src/{same_version_catalog,catalog_write,template_store}.rs`, `crates/verify/src/btree_walk.rs`, `crates/plan/src/version_pair.rs` (모두 @5a134ee).
- 실행 증거(이 문서): `.git_ignored_dir/scratch/map472-pairs/527/v114clean-target.jsonl`(59건), `v114clean-source.jsonl`(0건), `v114dirty-target.jsonl`.
- 앞선 조사: R1~R7, R8 `research/fastmig-r8-older-pairs`, R9 `research/fastmig-r9-tde`, R10 `research/fastmig-r10-user-schema`, #474 리드 코멘트, #503·#505 코멘트(59건의 원 기록).
