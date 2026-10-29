# R16 — 11.3·11.4 DEDUPLICATE 인덱스의 실재와 재빌드 규칙 (#532)

지도 xmilex-git/workspace#472, 티켓 #532. 근거 문서: R15 `research/fastmig-r15-target-114` (`bf128fa`) § B1~B14.
정적 조사다. 서버·DB·빌드는 쓰지 않았다. 런타임 확인이 필요한 주장은 [VERIFY]로 표시하고 probe를 적었다.

인용 형식은 `path:line@ref`다. ref는 `11.3` = `origin/release/11.3`, `11.4` = `origin/release/11.4`, `dev` = `origin/develop`(`5cd1de888`)이다. fastmig 인용은 `~/dev/cubrid-fastmig` `14079bf` 기준이다.

## 1. 질문

1. DEDUPLICATE 기능은 어느 릴리스 선에 있는가? 시스템 파라미터와 기본값은 무엇인가?
2. 출발 DB에 DEDUPLICATE 인덱스가 실제로 있을 수 있는가? T1/T4 기준 DB에는 있는가?
3. DDL 문법은 무엇인가? PK/UNIQUE/FK 가운데 무엇이 DEDUPLICATE가 될 수 있는가?
4. 클래스 객체·`_db_index`·disk repr·B-tree 루트는 이것을 어떻게 기록하는가? plan이 출발 카탈로그에서 무엇으로 감지하는가?
5. 숨은 열의 도메인, 값 공식, 다중 열 키 안의 위치, 루트 off70 인코딩은 무엇인가?
6. 정렬 기반 일괄 빌드와 온라인 삽입은 숨은 값을 같게 계산하는가? 공식의 pageid는 무엇의 pageid인가?
7. 함수 인덱스와 겹치면 위치가 어떻게 되는가?
8. develop(#8104)은 DEDUPLICATE 인덱스가 있는 출발을 어떻게 다루는가?

## 2. 결론

### 2.1 판정 표

| # | 항목 | 판정 | 근거 절 |
|---|---|---|---|
| 1 | 기능이 있는 선 | **11.3과 11.4만** 있다. 10.2·11.0·11.1·11.2에는 없다. develop은 #8104로 지웠다 | §3.1 |
| 2 | 파라미터 | `deduplicate_key_level`, 범위 −1..14, **기본 −1**(11.3·11.4 같음). client·server·session 파라미터이고 사용자가 바꿀 수 있다 | §3.2 |
| 3 | 기본값 −1의 뜻 | **절대 비활성**이다. 명시한 `WITH DEDUPLICATE=n`도 무시하고 level 0(없음)으로 만든다 | §3.2 |
| 4 | 출발 DB에 있을 수 있나 | 인덱스나 FK를 만들 때 그 세션의 `deduplicate_key_level`이 0 이상이었을 때만 생긴다. 한번 생기면 파라미터를 되돌려도 남는다. **기본 설정 DB에는 없다.** 고객 DB에는 정적으로 배제할 수 없다 | §3.2, §3.4 |
| 5 | T1/T4 기준 DB | **없다.** build.sh가 쓰는 conf에 `deduplicate_key_level`이 없으므로 기본값 −1이다. SQL 스크립트에 `DEDUPLICATE`가 없다. 11.4 기준 DB의 unload는 모든 인덱스와 FK를 `WITH DEDUPLICATE=0`으로 찍었다 | §3.10 |
| 6 | 대상 제약 | 비유니크 INDEX, REVERSE INDEX, FOREIGN KEY. PK와 UNIQUE는 안 된다(UNIQUE와 같이 쓰면 문법 오류). 예외 둘: prefix 인덱스, 그리고 키 열(함수 인자 제외)이 같은 클래스의 PK/UNIQUE 열을 모두 덮는 인덱스·FK는 숨은 열을 붙이지 않는다 | §3.3 |
| 7 | 숨은 열 도메인 | `SHORT`(`tp_Short_domain`). 속성 ID는 `0x8A8B8C90 − level`(int로 −1970566000 − level), 이름은 `_dedup_NN` | §3.5 |
| 8 | 값 공식 | `(short)(OID.pageid % 2^level)`. OID는 **그 행의 객체 OID(홈 슬롯)**다. 다만 숨은 열보다 앞선 실제 키 원소(함수 결과 포함)가 모두 NULL이면 숨은 원소도 NULL이다 | §3.6 |
| 9 | 일괄 빌드 대 온라인 삽입 | **같다.** 둘 다 `dk_get_deduplicate_key_value(rec_oid, ..)`를 부르고, rec_oid는 일괄 빌드에서 heap 스캔의 `cur_oid`, DML에서 `inst_oid`/`oid`다. 같은 행이면 같은 OID다 | §3.6 |
| 10 | MIDXKEY 안 위치 | **항상 마지막 원소**다. 함수 인덱스도 마찬가지다. R15 §2.6의 "MIDXKEY 끝(함수 열 앞)"은 정정한다. "함수 앞"은 제약의 **속성 목록**에서의 위치이고, 키 안에서는 함수 결과 뒤에 온다 | §3.7 |
| 11 | 루트 off70 | 16비트 `deduplicate_key_idx + 1`. DEDUPLICATE 인덱스면 값이 **키 원소 수 K**(숨은 열 포함)다. 아니면 0이다. off68 = `rev_level` = 0이다 | §3.8 |
| 12 | 출발 카탈로그에서 감지 | 클래스 객체 인덱스 property 시퀀스에 `[0x8A8B8C90−14, 0x8A8B8C90−1]` 범위 속성 ID가 있으면 DEDUPLICATE다. 같은 사실이 `_db_index_key.key_attr_name = '_dedup_NN'` 행, `_db_index.key_count = n+1`, 루트 off70 ≠ 0에도 보인다 | §3.4 |
| 13 | develop(#8104) | 기능을 지웠다. `WITH DEDUPLICATE = n`은 문법만 받고 버린다. 파라미터는 받고 무시한다. 출발 B-tree나 숨은 속성 ID를 읽는 호환 코드는 **없다**. 그래서 develop에 도착하면 숨은 열을 뺀 **일반 인덱스**로 다시 지어야 한다. 엔진의 참조 경로(11.4 unloaddb → develop loaddb)도 같은 결과(일반 인덱스)를 낸다 | §3.9 |

### 2.2 fastmig에 바로 걸리는 발견 (정적 판독, 추론)

- **F1. 이연 인덱스 DDL이 DEDUPLICATE 함수·필터 인덱스에서 실패한다.** `deferred_indexes`가 출발 제약을 그대로 담는다. `create_index`는 키 속성 ID마다 클래스 속성을 찾다가 숨은 ID에서 `"key attribute .. not in the class"` 오류를 낸다(fastmig `crates/catalog/src/class_rewrite.rs:315-324`, `crates/catalog/src/output_sql.rs:87-99, 126-130`).
- **F2. 일반 DEDUPLICATE 인덱스의 prefix 시퀀스가 develop에서 원소 수 1개를 넘는다.** class_rewrite는 숨은 `(id, asc_desc)` 쌍을 지운다. 그러나 비FK·비PK 제약의 optional 시퀀스(prefix 길이, n+1개)는 그대로 둔다(`class_rewrite.rs:156-187`). develop은 `assert (set_size (prefix_seq) == num_attrs)`로 검사한다(`src/object/class_object.c:2955@dev`). 11.4는 숨은 열까지 세어 n+1개를 쓴다(`src/object/class_object.c:1069-1086, 1149-1157@11.4`). 그래서 optdebug develop은 클래스를 읽을 때 assert가 난다. release는 앞 n개만 읽으므로 값은 맞다.
- 두 결함 모두 T1/T4 기준 DB로는 드러나지 않는다. 기준 DB에 DEDUPLICATE 인덱스가 없기 때문이다(§3.10).

## 3. 근거

### 3.1 기능이 있는 선

- `src/object/deduplicate_key.{h,c}`는 release/11.3과 11.4에만 있다. 10.2·11.0·11.1·11.2 트리에는 `dedup` 문자열이 0건이다(`git grep -c -i dedup origin/release/<r> -- src`).
- 도입 커밋은 `7add5356d` [CBRD-24478] #4401이다. 이 커밋은 release/11.2의 조상이 아니다(`git merge-base --is-ancestor 7add5356d origin/release/11.2` 거짓). 11.3의 후속 정리 커밋: `0c5f9d45f` CBRD-24928(FK가 UNIQUE 검사 오류로 level을 받던 문제), `f8e6c9c37` CBRD-24930(UNIQUE+DEDUPLICATE를 문법 오류로), `faaa55577` CBRD-24991(정리), `4d2bdceaf` CBRD-25327(cubrid.conf 줄 삭제).
- 11.3과 11.4의 `deduplicate_key.c` 차이는 include 한 줄과 개발자 전용 `OID_2_BIGINT` 매크로뿐이다(`git diff origin/release/11.3 origin/release/11.4 -- src/object/deduplicate_key.c`). 개발자 매크로는 `is_test_for_developer = false`인 `#ifndef NDEBUG` 블록 안에 있어서 실행되지 않는다(`src/object/deduplicate_key.c:151-162@11.4`).
- 11.3과 11.4의 heap 키 생성 차이는 MIDXKEY 헤더 형식(bound bits → `or_multi_*` 헤더와 원소 offset)뿐이다. 숨은 값 계산과 `not_null_field_cnt` 조건은 같다(`git diff origin/release/11.3 origin/release/11.4 -- src/storage/heap_file.c`의 `heap_midxkey_key_get`/`_generate` hunk). MIDXKEY 헤더 차이는 R8/R15 범위다.
- develop: `5de66400a` [CBRD-27324] #8104 "Remove the DEDUPLICATE index feature"(2026-10-14)가 `deduplicate_key.{c,h}`를 지웠다. `d8903061c`가 남은 include를 지웠다.

### 3.2 시스템 파라미터와 기본값

- 상수: `DEDUPLICATE_ABSOLUTE_DISABLE (-1)`, `LEVEL_OFF 0`, `LEVEL_MIN 1`, `LEVEL_MAX 14`, `SYSPARAM_DFLT = DEDUPLICATE_ABSOLUTE_DISABLE`(`src/object/deduplicate_key.h:36-45@11.4`, 11.3 같음).
- 파라미터 이름 `deduplicate_key_level`(`src/base/system_parameter.c:759@11.4`, `:737@11.3`). 기본값·하한·상한 변수(`:1256-1261@11.4`, `:1220-1225@11.3`). 플래그 `PRM_FOR_SERVER | PRM_FORCE_SERVER | PRM_FOR_CLIENT | PRM_FOR_SESSION | PRM_USER_CHANGE | PRM_FOR_HA_CONTEXT`(`:6435-6447@11.4`, `:6330-6342@11.3`). 숨김 파라미터가 아니고, 사용자가 세션에서 바꿀 수 있다.
- −1의 의미: CREATE INDEX 경로는 파라미터가 −1이면 문장의 level을 `DEDUPLICATE_KEY_LEVEL_OFF`로 덮어쓴다(`src/query/execute_schema.c:2936-2942@11.4`, `:2804@11.3`). FK 경로도 같다(`:7676-7680@11.4`, `:7541@11.3`).
- 파라미터가 0 이상일 때: 문장에 WITH 절이 없으면(`DEDUPLICATE_OPTION_AUTO = -2`, `csql_grammar.y:22495-22509@11.4`) 파라미터 값이 level이 된다. 명시 level은 그대로 쓴다(`execute_schema.c:2945-2955@11.4`, `:7683-7688@11.4`). 그래서 `deduplicate_key_level=n>0`인 서버에서 만든 비유니크 인덱스와 FK는 WITH 절이 없어도 모두 숨은 열을 얻는다.
- 배포 conf: 11.3.0 `conf/cubrid.conf`에는 `deduplicate_key_level=-1`과 주석 "-1 forces explicit statements to also be ignored."가 있었다. `4d2bdceaf`(11.3.1)가 그 줄을 지웠다. 어느 쪽이든 값은 −1이다.
- 사용자 매뉴얼도 같은 의미를 적었다: "If deduplicate_key_level is -1, it is internally ignored and not applied even if it is specified explicitly"(`~/dev/cubrid-manual/en/sql/schema/index_stmt.rst:277`, `en/admin/config.rst:2583`). 매뉴얼은 보조 근거다.
- 시스템 클래스 인덱스: 숨은 열 이름을 키 목록에 넣는 곳은 `execute_schema.c`의 두 곳(인덱스 `:3040`의 `dk_create_index_level_adjust`, FK `:7719`)뿐이다. 그 밖의 `dk_get_deduplicate_key_attr_name`/`dk_find_sm_deduplicate_key_attribute` 사용처는 이미 있는 이름을 다시 해석한다(`schema_template.c:2014-2067@11.4`, `class_object.c:8266-8273@11.4`). 추론: createdb의 시스템 카탈로그 설치는 DDL 실행기(`execute_schema.c`)를 거치지 않으므로 시스템 인덱스는 DEDUPLICATE가 되지 않는다. [VERIFY V6]

### 3.3 문법과 대상 제약

- `CREATE [REVERSE] INDEX name ON t (cols) [WHERE ..] WITH DEDUPLICATE = n [, ONLINE [PARALLEL k]]`. WITH 항목 순서는 어느 쪽이든 된다(`csql_grammar.y:22504-22541@11.4`). n은 0..14이고, 범위를 벗어나면 문법 오류다(`:22563-22575@11.4`).
- `CREATE UNIQUE INDEX .. WITH DEDUPLICATE = n`은 오류 "UNIQUE and DEDUPLICATE cannot be specified together."다(`csql_grammar.y:2927-2931@11.4`, `:2867@11.3`).
- 테이블 정의 안 인덱스 `INDEX name (cols) [WHERE ..] WITH DEDUPLICATE = n`(`attr_index_def`, `csql_grammar.y:10888-10949@11.4`).
- FK: `FOREIGN KEY [name] (cols) WITH DEDUPLICATE = n REFERENCES ..`(`csql_grammar.y:10151-10171@11.4`). 열 수준 FK: `[CONSTRAINT c] [FOREIGN KEY] WITH DEDUPLICATE = n REFERENCES ..`(`:11322-11344@11.4`).
- 실행 단계에서 대상은 `DB_CONSTRAINT_INDEX`와 `DB_CONSTRAINT_REVERSE_INDEX`만이다(`execute_schema.c:2936@11.4`). PK와 UNIQUE는 이 경로로 숨은 열을 얻지 않는다.
- prefix 인덱스는 제외한다: `idx_info->prefix_length == NULL`일 때만 숨은 열을 붙인다(`execute_schema.c:2951@11.4`).
- PK/UNIQUE 덮음 예외: `classobj_check_attr_in_unique_constraint`가 참이면 붙이지 않는다(인덱스 `execute_schema.c:3037-3041@11.4`, FK `:7716-7720@11.4`). 이 함수는 같은 클래스의 unique 계열 제약 가운데, 그 제약의 모든 열이 새 인덱스의 비함수 열 안에 있는 것이 하나라도 있으면 참을 낸다(`class_object.c:4071-4130@11.4`).
- 필터 인덱스(WHERE)와 함수 인덱스는 제외하지 않는다. 둘 다 DEDUPLICATE가 될 수 있다.

### 3.4 기록 위치 (plan 감지 근거)

1. **클래스 객체의 인덱스 property 시퀀스.** `classobj_put_index`는 `{btid 문자열, (attr_id, asc_desc)*, optional, status, comment}`를 쓴다. 숨은 열도 `con->attributes`의 원소라서 음수 ID와 asc_desc 쌍으로 들어간다(`class_object.c:1068-1086@11.4`). optional은 PK/FK가 아니고 필터·함수 정보가 없으면 prefix 길이 시퀀스이고, 원소 수는 숨은 열을 포함한 `num_attrs`다(`:1145-1157@11.4`). 함수 인덱스면 optional 안 `*FI*` 정보에 `attr_index_start`가 들어간다(`:1189-1198`, `:8443@11.4`). 이 값은 숨은 열 때문에 1 늘어난 값이다(§3.7).
2. **클래스 속성 목록에는 없다.** 숨은 속성은 프로세스마다 정적으로 만든 의사 속성이다. 주석은 "Make sure this isn't saved on disk !"다(`deduplicate_key.c:200-242@11.4`). ID나 이름으로 찾다가 실패하면 그 의사 속성을 돌려준다(`class_object.c:2576-2594@11.4`). 서버의 `or_install_btids_class`도 같은 방식이다(`object_representation_sr.c:1956-1960@11.4`). 그래서 `_db_attribute` 행도, heap 레코드의 값도 없다(`heap_file.c:10147-10150@11.4` 주석 "there is no content that actually exists in HEAP").
   - R15 §6 표의 "11.3: 88B + DEDUP 의사 속성"은 정확히 말하면 이렇다: 클래스 객체 레코드 형식은 같고, 흔적은 제약 시퀀스의 음수 속성 ID 하나다.
3. **`_db_index_key`.** catcls 변환은 키 속성 ID를 이름으로 바꾸고, 숨은 ID는 `_dedup_NN`이 된다(`catalog_class.c:874-886@11.4`). `db_index` 뷰는 `key_attr_name LIKE '_dedup_%'` 행이 있으면 `key_count - 1`을 보인다(`schema_system_catalog_install_query_spec.cpp:770-780@11.4`). 따라서 `_db_index.key_count`는 숨은 열을 포함한다. 뷰의 `is_deduplicate`, `deduplicate_key_level` 열은 `#if 0`으로 꺼져 있다(`schema_system_catalog_install.cpp:1622-1625@11.4`, query spec `:783-807`).
4. **B-tree 루트 off70**(§3.8)과 **루트 key domain**: MIDXKEY에 SHORT 원소가 하나 더 있다(`schema_manager.c:10742-10748@11.4`, `construct_index_key_domain :10375-10455`).
5. **disk repr 통계**(`BTREE_STATS`): `pkeys_size = tp_domain_size(key_type->setdomain)`라서 숨은 열을 포함한다. `dedup_idx`는 루트에서 읽어 메모리에만 둔다(`object_representation_sr.c:385-390@11.4`). `index_cardinality()`는 `dedup_idx > 0`이면 열 수를 하나 줄여 보인다(`system_catalog.c:5429-5436@11.4`).
6. **자동 생성 이름.** `sm_produce_constraint_name`은 FK일 때만 숨은 이름을 뺀다(`schema_manager.c:14284-14293@11.4`). 그래서 이름 없이 만든 DEDUPLICATE 인덱스의 이름에는 `__dedup_NN`이 붙는다. 예: `i_t_a__dedup_03`. 추론이다. [VERIFY V5]

plan 감지 규칙(제안): 출발 선이 11.3 또는 11.4이고, 인덱스 제약의 키 속성 ID가 `DEDUP_ID_BASE − 14 ..= DEDUP_ID_BASE − 1`이면 DEDUPLICATE다. level은 `DEDUP_ID_BASE − id`다(`deduplicate_key.h:51, 64-65, 75-78@11.4`). fastmig는 이미 같은 범위 상수를 쓴다(`crates/catalog/src/class_rewrite.rs:34-35, 163`).

### 3.5 숨은 열의 도메인과 키 인코딩

- 도메인은 `tp_Short_domain`이다(`deduplicate_key.c:59-68`의 OR 속성, `:207-228`의 SM 속성@11.4).
- `assert (CALC_MOD_VALUE_FROM_LEVEL (level) <= SHRT_MAX)`라서 값은 `0 .. 2^level − 1`(최대 16383)이다(`deduplicate_key.c:66, 164@11.4`).
- 키 이미지: `mr_index_writeval_short`는 `or_put_data(buf, &s, tp_Short.disksize)`로 **호스트 바이트 순서 2B**를 쓴다(`object_primitive.c:2669-2676@11.4`). x86-64에서는 little-endian이다. [VERIFY V1]
- asc/desc: REVERSE INDEX면 1(DESC), 아니면 0이다(`deduplicate_key.c:329@11.4`). 키 domain의 `is_desc`도 이 값을 따른다(`heap_file.c:12667-12670@11.4`). 사용자 열이 DESC여도 숨은 열은 ASC다.

### 3.6 값 공식과 일괄 빌드·온라인 삽입의 일치

- 공식: `db_make_short (value, (short) (rec_oid->pageid % CALC_MOD_VALUE_FROM_LEVEL (level)))`, `CALC_MOD_VALUE_FROM_LEVEL(lv) = 1u << lv`(`deduplicate_key.c:45, 141-168@11.4`; `:43, 140-163@11.3`). `level = 0x8A8B8C90 − att_id`(`deduplicate_key.h:65@11.4`). volid와 slotid는 쓰지 않는다.
- NULL 규칙: 키를 만드는 두 함수 모두 숨은 원소 앞에 NULL이 아닌 원소(함수 결과 포함)가 하나라도 있을 때만(`not_null_field_cnt > 0`) 숨은 값을 쓴다. 그렇지 않으면 NULL이다(`heap_midxkey_key_get` `heap_file.c:12619-12632@11.4`, `heap_midxkey_key_generate` `:12815-12829@11.4`; 11.3 `:12559`, `:12733`). 숨은 원소는 마지막이므로(§3.7) 이 경우는 실제 키 원소가 모두 NULL인 키다. 모두 NULL인 키는 B-tree에 넣지 않고 NULL 수만 센다(`btree_load.c:3428-3436@11.4`). 그러니 트리 안의 키에서 숨은 원소는 항상 NOT NULL이다(추론).
- 일괄 빌드(`btree_load_index` → sort → `btree_sort_get_next`): heap 스캔 `heap_next(.., &sort_args->cur_oid, ..)`가 내준 OID로 `heap_attrinfo_generate_key(.., &sort_args->cur_oid)`를 부른다(`btree_load.c:3283, 3402-3405@11.4`; 11.3 `:3411`). `heap_next`가 내주는 OID는 레코드의 홈 OID다(추론. REC_RELOCATION/REC_BIGONE도 홈 슬롯 OID로 스캔된다).
- 온라인 DML: insert/delete `locator_add_or_remove_index` → `heap_attrvalue_get_key(.., inst_oid, ..)`(`locator_sr.c:7885-7887@11.4`). update `locator_update_index` → `heap_attrvalue_get_key(.., oid, ..)`(`:8500-8505@11.4`). 그 밖의 호출(`:9030`, `:9470`, `:9921`, `:12470@11.4`)도 객체 OID를 넘긴다.
- 결론: 두 경로 모두 **객체 OID(홈 슬롯)의 pageid**를 쓴다. MVCC update는 OID를 바꾸지 않으므로 같은 행의 숨은 값은 update 뒤에도 같다(추론. 숨은 값이 OID만의 함수라는 사실에서 나온다). 배치 보존 복사는 OID를 바꾸지 않는다. 그러므로 **도착 OID에서 숨은 값을 다시 계산하면 출발 트리의 값과 같다.**
- 정렬 순서: 숨은 원소는 MIDXKEY의 일반 원소다. 일괄 빌드는 (사용자 열…, SHORT) 전체로 비교한다. 그래서 같은 사용자 키도 `pageid % 2^level` 값마다 다른 키가 되고, 리프 레코드가 나뉜다. 이것이 기능의 목적이다(매뉴얼 index_stmt.rst:248-250).

### 3.7 다중 열 키 안의 위치, 함수 인덱스와의 관계

DDL 실행기는 열 이름 배열 `attnames`를 이렇게 만든다(`execute_schema.c:2983-3041@11.4`, `dk_create_index_level_adjust` `deduplicate_key.c:289-332@11.4`).

- 함수 인덱스가 아니면 숨은 이름을 **맨 끝**에 붙인다(`deduplicate_key.c:319-322`).
- 함수 인덱스는 파서가 열 목록을 `[일반 열 n0개, 함수 인자 nargs개]`로 바꾼다. `attr_index_start = nnames − func_no_args = n0`이다(`execute_schema.c:3021-3022@11.4`). adjust는 함수 인자를 한 칸 뒤로 밀고 숨은 이름을 `attr_index_start` 자리에 넣은 뒤 `attr_index_start++` 한다(`deduplicate_key.c:301-318@11.4`). 그러므로 **속성 목록**은 `[일반 열 n0, _dedup_NN, 함수 인자…]`이고, 저장되는 `attr_index_start`는 n0+1이다. `col_id`(함수 결과의 키 위치)는 바뀌지 않는다.
- **키(MIDXKEY)** 는 `heap_midxkey_key_get`/`_generate`가 만든다. 함수 결과가 있으면 원소 수는 `attr_index_start + 1`이다(`heap_file.c:12544-12547`, `:12774-12778@11.4`). 속성 목록을 0번부터 돌면서 `i == col_id`이면 함수 결과를 먼저 쓴다(`:12568-12611`, `:12791-12811@11.4`). `col_id ≤ n0`이므로 함수 결과는 숨은 속성(목록의 n0번)보다 먼저 나온다. 그러므로 키는 `[일반 열들 사이 col_id 자리에 함수 결과, …, 숨은 SHORT]`이고, **숨은 원소는 언제나 마지막(K−1번)** 이다. 키 domain도 같은 순서로 만든다(`construct_index_key_domain(attr_index_start, ..)` `schema_manager.c:10742-10743, 10423-10438@11.4`).
- `dk_get_deduplicate_key_position(n_attrs, attr_ids, func_attr_index_start)`: 함수 인덱스면 `attr_ids[func_attr_index_start − 1]`이 숨은 ID일 때 `func_attr_index_start`(= n0+1 = K−1)를, 아니면 마지막 속성이 숨은 ID일 때 `n_attrs − 1`(= K−1)을 낸다. 그 밖에는 −1이다(`deduplicate_key.c:120-139@11.4`). 클라이언트 쪽 `dk_sm_deduplicate_key_position`도 같은 규칙이다(`:267-287@11.4`). 두 경우 모두 결과는 **키 안의 숨은 원소 위치 = K−1**이다.
- 예(추론, [VERIFY V2]):
  - `CREATE INDEX i ON t(a, b) WITH DEDUPLICATE=3` → 속성 `[a, b, _dedup_03]`, 키 `[a, b, S]`, idx 2, off70 = 3.
  - `CREATE INDEX i ON t(lower(b), a) WITH DEDUPLICATE=2` → 속성 `[a, _dedup_02, b]`, `attr_index_start` 2, `col_id` 0, 키 `[lower(b), a, S]`, idx 2, off70 = 3.
  - `CREATE INDEX i ON t(upper(name)) WITH DEDUPLICATE=4` → 속성 `[_dedup_04, name]`, `attr_index_start` 1, 키 `[upper(name), S]`, idx 1, off70 = 2. 이때 제약 시퀀스의 **첫 속성 ID가 숨은 ID**다. 서버는 이 경우 첫 실제 열을 3번 원소에서 읽는다(`object_representation_sr.c:2270-2288@11.4`).
- unloaddb도 같은 위치 규칙을 쓴다. 함수 인덱스면 `k--`로 속성 목록 위치로 바꾸고, 숨은 열은 찍지 않고 `WITH DEDUPLICATE=n`만 찍는다(`unload_schema.c:3742-3760@11.4`).

### 3.8 루트 헤더 off68/off70

- `BTREE_ROOT_HEADER`: node 헤더 32B(split_info 8 + prev/next VPID 16 + node_level 2 + max_key_len 2 + common_prefix 4) 다음에 `num_oids`@32, `num_nulls`@40, `num_keys`@48, `topclass_oid`@56, `unique_pk`@64가 오고, `_32 { int rev_level:16; int deduplicate_key_idx:16; }`@68이 온다(`btree_load.h:193-230@11.4`, `storage_common.h:140-144@11.4`). 11.3도 같다(`btree_load.h:224-230@11.3`).
- `SET_DECOMPRESS_IDX_HEADER(hdr, idx)`는 `deduplicate_key_idx = idx + 1`을 쓰고, GET은 1을 뺀다(`btree_load.h:221-222@11.4`).
- 쓰는 곳은 두 군데다.
  - 일괄 빌드: `btid_int.deduplicate_key_idx = dk_get_deduplicate_key_position(..)`(`btree_load.c:929@11.4`, `:931@11.3`)를 거쳐 `SET_DECOMPRESS_IDX_HEADER(root_header, load_args->btid->deduplicate_key_idx)`(`:1918-1919@11.4`, `:1926@11.3`).
  - 빈 인덱스와 온라인 인덱스: `allocate_index`가 `btree_add_index(.., dk_sm_deduplicate_key_position(n_attrs, attrs, function_index))`를 부른다(`schema_manager.c:10830-10835@11.4`, `:10990@11.3`). 그 안에서 `SET_DECOMPRESS_IDX_HEADER(root_header, deduplicate_key_pos)`(`btree.c:5827-5829@11.4`, `:5630@11.3`).
- `rev_level = BTREE_CURRENT_REV_LEVEL = 0`(`btree_load.h:51@11.3/11.4`).
- GCC x86-64 비트필드는 낮은 비트부터 채운다. 그래서 off68–69 = `rev_level`(0), off70–71 = `idx+1`(LE i16)이다. 32비트 LE 워드로 보면 `(idx+1) << 16`이다. R15 B5, fastmig `RootHeader::dedup_key_idx_114`(`crates/ondisk/src/btree/root_header.rs:27-30, 76-80`)와 맞는다. [VERIFY V1]
- 값: DEDUPLICATE 인덱스면 idx = K−1이므로 **off70 = K**(숨은 열을 포함한 키 원소 수)다. 아니면 idx = −1이므로 0이다.
- 읽는 곳: `btree_glean_root_header_info`가 `btid->deduplicate_key_idx`에 넣는다(`btree.c:6007-6009@11.4`). 통계의 `same_prefix_len`(`btree.c:7507@11.4`, `:8955@11.3`)과 disk repr 통계(`object_representation_sr.c:389@11.4`)가 쓴다. **키를 만드는 경로는 off70을 쓰지 않는다.** 숨은 값은 속성 ID로만 정해진다(§3.6). 그러므로 off70이 틀려도 DML은 맞는 키를 만든다. 틀리는 것은 통계와 `index_cardinality`다(R15 L7과 같은 판단).

### 3.9 develop(#8104)

- 커밋 메시지(`5de66400a`): "WITH DEDUPLICATE = n is still accepted for indexes and foreign keys and ignored.", "deduplicate_key_level is deprecated; print_index_detail and unloaddb --skip-index-detail are removed.", "Drop the hidden dedup key column handling from btree, heap, FK checks, statistics, optimizer and schema code.", "unloaddb no longer prints WITH DEDUPLICATE=0; the btree root header layout is unchanged."
- 문법: `deduplicate_key_mod_level : DEDUPLICATE_ '=' unsigned_integer { }` — 받고 버린다(`src/parser/csql_grammar.y:20086-20090@dev`). 파라미터는 "accepted and ignored"(`src/base/system_parameter.c:4969-4971@dev`).
- 루트: `int rev_level`@68 4B(`src/storage/btree_load.h:258-274@dev`). 11.4 DEDUPLICATE 루트를 develop이 그대로 읽으면 `rev_level = (K << 16)`이 된다. 추론: 그래서 도착 develop은 off68 = 0으로 다시 지어야 한다. fastmig의 develop 빌드는 이미 0을 쓴다(R15 B5).
- 숨은 속성 ID 호환 코드는 없다.
  - 서버 `or_install_btids_class`는 ID가 맞는 속성을 찾지 못하면 그 키 원소를 조용히 빼고 `n_atts`를 하나 덜 센다(`src/base/object_representation_sr.c:1941-1960@dev`).
  - 클라이언트 `classobj_make_class_constraints`는 속성을 찾지 못하면 그 제약의 속성 배열 전체를 NULL로 만든다(`src/object/class_object.c:3282-3303, 3329-3339@dev`).
  - 추론: 숨은 ID가 남은 클래스 객체는 develop에서 깨진 제약이 된다. 숨은 ID는 반드시 지워야 한다.
- 엔진 참조 경로: 11.4 unloaddb는 DEDUPLICATE 인덱스를 `CREATE INDEX [name] ON .. (실제 열) WITH DEDUPLICATE=n`으로 찍는다. FK도 `FOREIGN KEY(..) WITH DEDUPLICATE=n`으로 찍는다(`unload_schema.c:3742-3760, 3853-3860, 4851-4880@11.4`). develop loaddb는 WITH 절을 버리므로 **같은 이름의 일반 인덱스**가 된다. 이것이 집합 비교의 기준이다. fastmig 정규화 규칙 `with-deduplicate-0`(`crates/cli/src/unload_normalize.rs:54-59`)은 level 0만 다룬다. level ≥ 1이면 `WITH DEDUPLICATE=n` 문자열이 출발 unload에만 남는다(추론).
- 11.4 unloaddb의 `--skip-index-detail`(기본 꺼짐)은 `print_index_detail`을 no로 만들어 `WITH DEDUPLICATE=` 출력을 끈다(`unloaddb.c:266-268@11.4`, `dk_print_deduplicate_key_info` `deduplicate_key.c:334-353@11.4`).

### 3.10 T1/T4 기준 DB와 스크립트

- `~/dev/cubrid-fastmig/basedb/`(`*.sql`, `10.2/`, `11.0/`, `11.2/`, `11.3/`, `build.sh`)와 `/home/cubrid/fastmig-basedb/scripts/`(`build.sh.orig-t4` 포함), `e2e/`, `tc/`에서 `dedup` 대소문자 무시 검색 결과는 0건이다.
- `build.sh`의 `write_conf`는 `[common]`에 `cubrid_port_id`, `data_buffer_size=512M`, SP 스위치, 그리고 추가 한 줄(`log_max_archives=0` 또는 dirty용 vacuum 설정)만 쓴다(`basedb/build.sh:51-61`). 그래서 `deduplicate_key_level`은 기본값 −1이다. 그 상태에서는 명시 DEDUPLICATE도 무시된다(§3.2).
- 증거: 11.4 dirty paramdump `deduplicate_key_level=-1`(`/home/cubrid/fastmig-basedb/11.4/evidence/dirty/paramdump.out:205`). 11.4 clean unload의 14개 `CREATE INDEX`와 3개 FK가 모두 `WITH DEDUPLICATE=0`이다(`/home/cubrid/fastmig-basedb/11.4/unload/clean/fm114_clean_indexes:1-14`, `fm114_clean_schema:318-322`). 함수 인덱스 `i_f1`·`i_f2`·`idx_g5_lower_email`과 필터 인덱스도 0이다.
- 11.3·11.2 기준 DB(T4 #512)는 아직 `/home/cubrid/fastmig-basedb/`에 없다(11.4, develop만 있음). 스크립트와 conf가 같으므로 만들어도 DEDUPLICATE 인덱스는 0개다(추론). [VERIFY V7]

## 4. fastmig에 대한 함의

| 모듈 / 티켓 | 할 일 |
|---|---|
| plan (P2a #535, 11.3 출발) | 감지만 한다: 11.3·11.4 출발에서 제약 키 ID가 dedup 범위면 인덱스별로 `level`과 `K`를 plan 출력에 적는다. 거부할 이유는 없다(develop 도착은 일반 인덱스로 짓는다). 10.2·11.2 출발에서 그 범위 ID가 보이면 구조 오류로 거부한다(기능이 없는 선이다) |
| catalog `class_rewrite` (develop 도착) | 숨은 `(id, asc_desc)` 쌍 제거는 이미 한다(`class_rewrite.rs:156-168`). **F2**: 일반 인덱스의 prefix 시퀀스에서 숨은 위치의 원소를 지워 n개로 맞춘다. 함수 인덱스는 이연되므로 develop 클래스 객체에 `*FI*`가 남지 않는다. 다만 이연을 풀 때가 오면 `attr_index_start − 1`도 필요하다 |
| catalog `output_sql::create_index` (이연 인덱스) | **F1**: 숨은 ID는 열로 찍지 않고 건너뛴다. 함수 인덱스면 `n_keys = attr_index_start + 1`에서 숨은 열 하나를 빼야 한다(11.4 저장값은 +1 되어 있다). `WITH DEDUPLICATE=n`은 develop이 무시하므로 붙이지 않는다 |
| catalog 재생성 (`_db_index`, `_db_index_key`) | develop 도착: `_dedup_NN` 행을 만들지 않고, `key_count`는 숨은 열을 뺀 수로 한다. 대상 클래스 객체에서 파생하면 저절로 된다(P1c G2 "DEDUP 속성 제거") |
| index build (develop 도착) | 숨은 열 없는 키로 짓는다. `index_def::index_shape`는 develop 클래스 객체(숨은 ID 제거 뒤)를 읽으므로 이미 맞다. 1열 DEDUPLICATE 인덱스는 develop에서 MIDXKEY가 아니라 단일 도메인 키가 된다. 이름은 그대로 둔다(`__dedup_NN` 꼬리가 있어도 그대로) |
| index build (11.4 도착, R15 B3·B4·B5) | key domain 끝에 SHORT(REVERSE INDEX면 DESC)를 붙인다. 함수 인덱스도 끝이다(R15 §2.6 정정). 키 생성은 각 행의 **도착 OID pageid** `% 2^level`을 쓰고, 앞의 실제 원소가 모두 NULL이면 NULL로 둔다(그 키는 넣지 않는다). 루트 off70 = K, off68 = 0. disk repr `BT_STATS` `pkeys_size`는 K다 |
| verify | 11.4 도착이면 DEDUPLICATE 인덱스를 `not_checked`로 두는 지금 처리(`crates/verify/src/run.rs:143-150`)를 V1~V3 결과가 나오면 바이트 검사로 바꿀 수 있다 |
| 집합 비교 정규화 | level ≥ 1 출발이 생기면 `WITH DEDUPLICATE=[1-9][0-9]?` 제거 규칙이 필요하다. 근거 커밋은 `5de66400a`다 |
| 기준 DB (T4 #512 또는 새 task) | DEDUPLICATE 경로를 e2e로 덮으려면, 11.3/11.4 기준 DB를 만들 때 해당 세션에서만 `SET SYSTEM PARAMETERS 'deduplicate_key_level=0'`을 걸고 명시 `WITH DEDUPLICATE=n` 인덱스(일반 2열, 1열, 함수, 필터, REVERSE, FK)를 만드는 스크립트를 따로 둔다. 기존 T1 기준 DB 정의는 바꾸지 않는다 |

## 5. [VERIFY] 목록

모든 probe는 11.4.6(`/home/cubrid/release/CUBRID-fastmig-11.4.6`) 또는 11.3 설치에서 작은 DB로 한다. CS 모드에서 서버를 띄울 때는 `cubrid-server-control`을 쓰고 포트를 claim한다.

- **V1. 루트 off68/off70과 숨은 원소 바이트.**
  - 주장: DEDUPLICATE 인덱스 루트 레코드(루트 페이지 slot 0) off68–69 = `00 00`, off70–71 = K(LE i16). 리프 키 마지막 원소는 2B LE SHORT `pageid % 2^level`이다.
  - probe: `csql -S`에서 `SET SYSTEM PARAMETERS 'deduplicate_key_level=0'; CREATE TABLE t (a INT, b VARCHAR(10)); INSERT INTO t SELECT MOD(ROWNUM,3), 'x' FROM db_class a, db_class b LIMIT 2000; CREATE INDEX i_ab ON t(a,b) WITH DEDUPLICATE=3; CREATE INDEX i_a ON t(a) WITH DEDUPLICATE=14;`. `SHOW INDEX CAPACITY OF t.i_ab`, `diagdb -d 1`(또는 fastmig `inspect` 계열 도구)로 루트 VPID를 얻고 slot 0 레코드 off68..72를 덤프한다. 리프 레코드 하나를 골라 키 MIDXKEY 마지막 원소 2B와, 그 레코드 OID의 pageid를 비교한다.
  - 기대: `i_ab` off70 = `03 00`, `i_a` off70 = `02 00`. 숨은 원소 = `pageid % 8`(i_ab), `pageid % 16384`(i_a).
- **V2. 함수 인덱스 위치.**
  - 주장: 키의 숨은 원소는 마지막이고, 저장된 `attr_index_start`는 n0+1이다.
  - probe: 같은 세션에서 `CREATE TABLE f (a INT, b VARCHAR(20)); INSERT ..; CREATE INDEX f1 ON f(lower(b), a) WITH DEDUPLICATE=2; CREATE INDEX f2 ON f(upper(b)) WITH DEDUPLICATE=4;`. fastmig 클래스 객체 디코더로 제약 시퀀스(키 ID 순서, `*FI*`의 `col_id`/`attr_index_start`)를 출력하고, 루트 off70과 루트 packed_key_domain 원소 순서를 덤프한다.
  - 기대: f1 속성 ID `[a, BASE−2, b]`, `attr_index_start` 2, `col_id` 0, domain `[VARCHAR, INT, SHORT]`, off70 3. f2 속성 `[BASE−4, b]`, `attr_index_start` 1, domain `[VARCHAR, SHORT]`, off70 2.
- **V3. 일괄 빌드와 온라인 삽입의 일치.**
  - 주장: 같은 행에 대해 CREATE INDEX 일괄 빌드와 뒤이은 DML이 같은 숨은 값을 낸다.
  - probe: V1 테이블에 인덱스를 만든 뒤 2000행을 더 INSERT하고 일부 UPDATE한다(키 열 아닌 열, 그리고 키 열). `checkdb`가 아니라 fastmig 검증기 또는 리프 덤프로, 모든 리프 키의 숨은 원소가 그 OID의 `pageid % 2^level`과 같은지 센다.
  - 기대: 불일치 0.
- **V4. prefix 시퀀스 원소 수(F2).**
  - 주장: 11.4 일반 DEDUPLICATE 인덱스 제약의 optional prefix 시퀀스는 n+1개다.
  - probe: V1 DB에서 fastmig 클래스 객체 디코더로 `i_ab` 제약의 optional 원소 수를 출력한다. 그다음 fastmig develop 도착 migrate(dry run 아님)를 하고, optdebug develop csql로 `SELECT * FROM t WHERE a = 1` 를 실행한다.
  - 기대: 원소 3개(−1, −1, −1). F2를 고치기 전에는 optdebug develop에서 `class_object.c:2955` assert, 고친 뒤에는 정상.
- **V5. 자동 이름.**
  - 주장: 이름 없는 DEDUPLICATE 인덱스의 이름은 `i_t_a__dedup_03` 꼴이다.
  - probe: `SET SYSTEM PARAMETERS 'deduplicate_key_level=0'; CREATE INDEX ON t(a) WITH DEDUPLICATE=3; SELECT index_name FROM db_index WHERE class_name='t';`
  - 기대: `i_t_a__dedup_03`.
- **V6. 시스템 인덱스.**
  - 주장: `deduplicate_key_level=5`로 createdb 해도 시스템 카탈로그 인덱스에는 숨은 열이 없다.
  - probe: conf에 `deduplicate_key_level=5`를 넣고 createdb한다. `SELECT COUNT(*) FROM _db_index_key WHERE key_attr_name LIKE '\_dedup\_%' ESCAPE '\';`를 실행한다. 이어서 사용자 `CREATE INDEX` 하나(WITH 절 없음)를 만들고 다시 센다.
  - 기대: createdb 직후 0. 사용자 인덱스 뒤 1(AUTO 적용 확인).
- **V7. 11.3·11.2 기준 DB.**
  - 주장: T4 기준 DB에 DEDUPLICATE 인덱스가 없다.
  - probe: T4 기준 DB가 생기면 `SELECT COUNT(*) FROM _db_index_key WHERE key_attr_name LIKE '\_dedup\_%' ESCAPE '\';`를 실행한다(11.3만 해당).
  - 기대: 0.
- **V8. develop 참조 경로.**
  - 주장: 11.4 unload(DEDUPLICATE=3 인덱스 포함)를 develop loaddb에 넣으면 같은 이름의 일반 인덱스가 생긴다.
  - probe: V1 DB를 11.4 unloaddb로 내리고, develop에서 createdb와 loaddb를 한 뒤 `SHOW INDEX FROM t`, `;plan simple`로 `SELECT * FROM t WHERE a=1 AND b='x'`의 INDEX SCAN을 확인한다.
  - 기대: `i_ab (a, b)`, 숨은 열 없음, 인덱스 스캔.

## 6. 새 질문

### 지금 정확히 말할 수 있는 것

- 숨은 값은 객체 OID만의 함수다. 배치 보존 복사에서는 다시 계산하든 출발 키에서 옮기든 결과가 같다(§3.6).
- 11.4 도착 재빌드 규칙(SHORT, 끝 위치, off70 = K)은 소스로 닫혔다. V1~V3는 바이트로 확인하는 일만 남았다.
- develop 도착은 일반 인덱스로 짓는 것이 엔진 참조 경로와 같다(§3.9).

### 아직 흐린 것

1. **같은 열의 일반 인덱스와 DEDUPLICATE 인덱스가 같이 있는 출발.** 11.4는 `(a)`와 `(a, _dedup_03)`을 다른 속성 목록으로 본다. 비유니크끼리는 숨은 열을 빼고 비교하는 예외가 없다(`class_object.c:4194-4269@11.4`, `is_compare_except_dedup_key`는 UNIQUE가 낄 때만 참). 추론: 두 인덱스가 같이 있을 수 있다. develop 도착에서 숨은 열을 빼면 열이 같은 인덱스 둘이 된다. develop이 이런 카탈로그를 받아들이는지, 참조 경로(develop loaddb)가 두 번째 `CREATE INDEX`에서 실패하는지는 모른다. probe: 11.4에서 `CREATE INDEX i1 ON t(a); CREATE INDEX i2 ON t(a) WITH DEDUPLICATE=3;`(param 0)이 되는지 보고, 되면 unload → develop loaddb 결과를 본다.
2. **FK 인덱스 공유.** FK가 이미 있는 DEDUPLICATE 인덱스를 `SHARED:`로 공유하는 경우가 있다(`class_object.c:8253-8282@11.4`). develop 도착에서 공유 관계가 그대로 맞는지는 소스만으로 다 보지 않았다.
3. **파티션 클래스.** 파티션마다 제약을 복사하므로 숨은 ID도 복사된다고 본다(추론). 숨은 값이 파티션 행 OID의 pageid라는 것은 §3.6과 같다. 파티션 경로의 키 생성 호출을 따로 확인하지 않았다.
4. **11.3 → 11.4 도착에서 MIDXKEY 헤더 형식**(bound bits → `or_multi_*`)이 바뀐다. 숨은 원소와 상관없이 R8/R15 재빌드가 다루는 일이지만, 11.3 출발 키를 옮기지 않고 다시 짓는다는 전제를 P2a가 지켜야 한다.
