# R4: 11.4와 develop의 `_db_*` 카탈로그 테이블·vclass 차이, upgradedb 스크립트 체인, Rust가 써야 할 카탈로그 행 (#476, map #472)

기준: develop = `/home/cubrid/dev/cubrid-worktree/develop` HEAD `5b1867174`, 11.4 = `origin/release/11.4` `46212adcd` (merge-base `13a115a0e`).
표기: `D:path:line`은 develop `5b1867174`, `R:path:line`은 `origin/release/11.4` `46212adcd`의 위치입니다. "(계산)"으로 표시한 값은 소스에서 읽은 것이 아니라 구조체 정의와 매크로로 계산한 것입니다.

## 0. 요약

1. 카탈로그 **테이블**은 11.4에 29개, develop에 30개 있습니다. 새로 생긴 것은 `_db_histogram`(aabba8d1e #7180)과 `_db_global_tran`(e651ed803 #6820)이고, 없어진 것은 `db_authorizations`(1f1263217 #6443)입니다. `db_serial`, `db_ha_apply_info`, `db_user`, `db_password`, `db_authorization`, `db_trigger`는 이름 앞에 `_`가 붙은 이름으로 바뀌었습니다(1f1263217 #6443, 8ba543178 #6903).
2. 카탈로그 **vclass**는 11.4의 20개에서 develop의 25개로 늘었고, 여기에 `INFORMATION_SCHEMA` 소유 뷰 19개(601f0c324 #7174)가 더해집니다. 소유자인 시스템 사용자 `INFORMATION_SCHEMA`도 새로 생겼습니다.
3. 칼럼 변경의 대부분은 #6443, #6903, #7874에서 왔습니다. 생성·수정 시각 칼럼, `flags`, `statistics_strategy`, `_db_index`의 FK 칼럼, `class_partition_type`, `start_val`, `is_loginable`/`is_system_created`가 추가됐고, `_db_index`의 `status`/`comment` 순서가 바뀌었습니다. 여기에 NUMERIC이 고정 길이에서 가변 길이로 바뀌어(de7bc5ec2 #6486) `_db_serial`의 레코드 배치가 달라집니다.
4. 이 문서의 "ct 테이블"은 `ct_Classes[]`에 등록된 11개입니다(`_db_class`, `_db_attribute`, `_db_domain`, `_db_method`, `_db_meth_sig`, `_db_meth_arg`, `_db_meth_file`, `_db_query_spec`, `_db_index`, `_db_index_key`, `_db_partition`). 이 행들은 **클래스 객체만으로 다시 만들 수 있는 파생 데이터**입니다. develop의 upgradedb도 이 11개를 truncate한 뒤 `sm_force_write_all_classes`로 다시 채웁니다. 따라서 Rust는 이 행을 변환하지 말고 develop의 `catcls_get_or_value_from_*` 규칙대로 새로 생성해야 합니다.
5. 나머지 카탈로그 테이블(사용자, 비밀번호, 권한, 트리거, 시리얼, SP, 동의어, 서버)은 원본 데이터입니다. 행마다 develop 포맷으로 다시 인코딩하고, 새 칼럼은 정해진 값으로 채워야 합니다(§7 R6~R14).
6. CBRD-26459(9ee8bac8b #7773)의 versioned 스크립트는 **현재 0개**입니다(`upgrade/`에 `v*_to_v*.sql` 없음). `SYSTEM_METADATA_VERSION`은 1이고 v0(11.5 이전) DB는 업그레이드할 수 없습니다. 그래서 11.4 → develop 전환에는 엔진이 실행할 체인이 없습니다. Rust가 할 일은 (a) 카탈로그를 v1 형태로 직접 만들고 (b) 로그 헤더 `sysmeta_version`(오프셋 102, 계산값)에 1을 쓰는 것입니다.
7. 카탈로그 행 OID 가운데 카탈로그 바깥에서 참조되는 것은 세 종류입니다. `_db_user` 행(클래스 객체의 owner), `_db_trigger` 행(클래스 객체의 trigger 목록, `db_root.triggers`, `_db_user.triggers`), `_db_stored_procedure` 행(`_db_auth.object_of`, `_db_authorization.grants`)입니다. 카탈로그 힙을 새 페이지에 할당하면 이 세 종류는 old→new OID 매핑으로 바꿔 써야 합니다(§6).
8. ct 테이블 안의 참조는 모두 카탈로그 행 OID(부모 행 역참조와 `_db_class` 행)이므로 새로 만들 때 함께 정해집니다. 예외로 `_db_class.class_of`, `_db_class.owner`, `_db_index.referential_class`는 원본 OID를 그대로 저장합니다.
9. develop은 부팅할 때 ct 칼럼 이름이 모두 있는지 이름으로 확인하고, `_db_class`/`_db_index`의 시각 칼럼이 고정 길이 영역에 있는지도 확인합니다. 이 조건을 어기면 부팅에 실패합니다(§7 R2, R3).
10. 열린 결정(§8)은 다섯 가지입니다. 비-ct 카탈로그 행을 같은 슬롯에 둘지 재할당할지, `start_val` 값, 시스템 vclass를 템플릿 DB에서 복사할지, 사용자 뷰가 바뀐 시스템 뷰에 의존하는 경우, dedup 키 칼럼을 어떻게 다룰지입니다.

## 1. 카탈로그 테이블과 vclass 목록

### 1.1 테이블 (heap을 가진 시스템 클래스)

| 11.4 이름 | develop 이름 | 생성 경로 (develop) | 변경 커밋 |
|---|---|---|---|
| `_db_class` … `_db_index_key`(10개), `_db_partition` | 동일 | `catcls_init` `D:src/object/schema_system_catalog_install.cpp:274-286` | §2 |
| `_db_auth` | 동일 | 같은 위치 `:284` | §2 |
| `_db_data_type` | 동일 | `:287` | bb8f3cbda #6420 (행 2개 삭제), 1f1263217 #6443 (PK) |
| `_db_stored_procedure`, `_args`, `_code` | 동일 | `:288-290` | §2 |
| `db_serial` | `_db_serial` | `:291` | 1f1263217 #6443 (`D:src/object/schema_system_catalog_constants.h:44` / `R:…constants.h:45`) |
| `db_ha_apply_info` | `_db_ha_apply_info` | `:292` | 같은 커밋 (`D:…constants.h:45`) |
| `_db_collation`, `_db_charset`, `dual`, `_db_synonym` | 동일 | `:293-296` | §2 |
| `_db_server` | 동일(매크로 이름만 `CT_DB_SERVER_NAME` → `CT_SERVER_NAME`) | `:297` | §2 |
| `db_trigger` (`tr_install`가 생성, `R:src/object/trigger_manager.c:7453`) | `_db_trigger` (catcls가 생성, `D:…install.cpp:285`) | `get_trigger` `D:…install.cpp:820` | 1f1263217 #6443 |
| `db_root` | 동일 | `au_install` `D:src/object/authenticate_context.cpp:302` | — |
| `db_user` | `_db_user` | `D:…authenticate_context.cpp:303,367-378` | 8ba543178 #6903 (`D:…constants.h:47`) |
| `db_password` | `_db_password` | `:304,417-421` | 8ba543178 #6903 |
| `db_authorization` | `_db_authorization` | `:305,443-444` | 8ba543178 #6903 |
| `db_authorizations` (`R:…authenticate_context.cpp:314,373-390`) | **없음** | — | 1f1263217 #6443 |
| 없음 | `_db_histogram` | `D:…install.cpp:298,1278` | aabba8d1e #7180 |
| 없음 | `_db_global_tran` | `D:…install.cpp:299,1308` | e651ed803 #6820 |

전체 목록의 근거는 `sm_system_class_names`입니다(`D:src/object/schema_system_catalog.cpp:39-90`, `R:…schema_system_catalog.cpp:33-87`). 11.4에는 `_db_resolution` 항목도 있지만 "not implemented"로 표시돼 있고 `catcls_init`에서 만들지 않으므로(`R:…install.cpp:204-252`) 클래스는 없습니다.

### 1.2 시스템 vclass

| 11.4 (20) | develop (25 + `INFORMATION_SCHEMA.*` 19) |
|---|---|
| `db_class`, `db_direct_super_class`, `db_vclass`, `db_attribute`, `db_attr_setdomain_elm`, `db_method`, `db_meth_arg`, `db_meth_arg_setdomain_elm`, `db_meth_file`, `db_index`, `db_index_key`, `db_auth`, **`db_trig`**, `db_partition`, `db_stored_procedure`, `db_stored_procedure_args`, `db_collation`, `db_charset`, `db_server`, `db_synonym` | 왼쪽 목록에서 `db_trig` 자리에 **`db_trigger`**(뷰), 그리고 새 뷰 **`db_serial`, `db_ha_apply_info`, `db_user`, `db_authorization`, `db_histogram`** |
| — | `INFORMATION_SCHEMA`.`column_privileges, columns, domains, foreign_servers, key_column_usage, parameters, partitions, referential_constraints, routine_privileges, routines, schemata, sequences, statistics, synonyms, table_constraints, table_privileges, tables, triggers, views` |

근거: `R:…schema_system_catalog.cpp:89-115`, `D:…schema_system_catalog.cpp:92-125`, `D:src/object/schema_information_schema_constants.h:28-46`, `D:…install.cpp:301-325`. 이름이 같은 뷰도 칼럼과 query spec이 바뀌었습니다(예: `db_class`에 `statistics_strategy`/`created_time`/`updated_time`/`checked_time` 추가, `D:…install.cpp:1340-1376`). Rust는 시스템 vclass를 develop 정의로 통째로 교체하므로 뷰별 spec 차이는 따로 정리하지 않았습니다(§7 R15).

## 2. 테이블별 칼럼 차이 (11.4 → develop)

"동일"은 칼럼 이름, 타입, 순서가 같다는 뜻입니다. 타입 표기는 정의 문자열 그대로입니다(`string` = `varchar(1073741823)`, 시퀀스 = `sequence of …`).

| 테이블 | 11.4 정의 | develop 정의 | 차이 | 커밋 |
|---|---|---|---|---|
| `_db_class` | `R:…install.cpp:366` 칼럼 25개 | `D:…install.cpp:435` 칼럼 30개 | `tde_algorithm` 뒤에 `statistics_strategy int`, `flags int` 추가. 끝에 `created_time`, `updated_time`, `checked_time` (datetime) 추가. 인덱스 `{class_of}` 추가. `INFORMATION_SCHEMA` SELECT 권한 | 1f1263217 #6443 |
| `_db_attribute` | `R::437` (11) | `D::510` (12) | `default_value` varchar(255)→varchar(2048)(`DB_MAX_DEFAULT_EXPR_LENGTH`, `D:src/compat/dbtype_def.h:553`). `is_nullable` 뒤에 `flags int` 추가 | 8ba543178 #6903 |
| `_db_domain` | `R::474` | `D::545` | 칼럼 동일(권한만 추가) | — |
| `_db_method`, `_db_meth_sig`, `_db_meth_arg`, `_db_meth_file` | `R::511/543/574/604` | `D::579/608/636/663` | 칼럼 동일 | — |
| `_db_query_spec` | `R::633` (2) | `D::689` (3) | `invalidated_time datetime` 추가 | 8ba543178 #6903 |
| `_db_index` | `R::661` (12, …`have_function, comment, status`) | `D::715` (20) | 순서가 `…have_function, status, referential_class object, delete_rule, update_rule, referential_match_option, index_type, options, comment, created_time, updated_time`로 바뀜. 인덱스 `{index_name}` 추가 | 1f1263217 #6443, `referential_class`는 1c5f1fd26 #7874 |
| `_db_index_key` | `R::699` | `D::759` | 동일 | — |
| `_db_auth` | `R::736` (6) | `D::788` (8) | `created_time`, `updated_time` 추가 | 1f1263217 #6443 |
| `_db_partition` | `R::769` (6) | `D::859` (7) | `pvalues` 뒤에 `class_partition_type int` 추가 | 1f1263217 #6443 |
| `_db_data_type` | `R::801`, 행 30개(`R::44-87`, NCHAR/VARNCHAR 포함) | `D::889`, 행 28개(`D::87-123`, 두 타입 NULL 처리) | PK `{type_id,type_name}` 추가. 행 2개 감소(계산: names[] 중 NULL이 아닌 항목 수) | bb8f3cbda #6420, 1f1263217 #6443 |
| `_db_stored_procedure` | `R::828` (14, `target_method` varchar(1024)) | `D::914` (17) | `owner` 뒤에 `sql_data_access int` 추가. 끝에 `created_time`, `updated_time` 추가. `target_method` varchar(4096)(`D:…constants.h:100`, `R:…constants.h:95`) | 1f1263217 #6443, a38948c99 #6427 |
| `_db_stored_procedure_args` | `R::866` | `D::954` | `default_value` varchar(255)→varchar(2048) | 8ba543178 #6903 |
| `_db_stored_procedure_code` | `R::900` | `D::986` | 동일 | — |
| `db_serial`→`_db_serial` | `R::933` (13, numeric(38,0) 고정 길이) | `D::1018` (16) | `min_val` 뒤에 `start_val numeric(38,0)`(기본값 1) 추가. 끝에 `created_time`, `updated_time` 추가. NUMERIC은 가변 길이로 바뀜(§3) | 1f1263217 #6443, de7bc5ec2 #6486 |
| `db_ha_apply_info`→`_db_ha_apply_info` | `R::1006` | `D::1063` | 칼럼 동일(이름만 변경) | 1f1263217 #6443 |
| `_db_collation` | `R::1068` | `D::1118` | PK `{coll_id}` 추가 | 1f1263217 #6443 |
| `_db_charset`, `dual` | `R::1100/1128` | `D::1149/1174` | 동일(`dual`에 `INFORMATION_SCHEMA` SELECT 추가) | — |
| `_db_synonym` | `R::1179` (8) | `D::1200` (10) | `created_time`, `updated_time` 추가 | 1f1263217 #6443 |
| `_db_server` | `R::1225` (9) | `D::1240` (12) | `created_time`, `updated_time`, `invalidated_time` 추가 | 1f1263217 #6443, 8ba543178 #6903 |
| `db_trigger`→`_db_trigger` | `R:…trigger_manager.c:7321-7420` (16) | `D::820` (18) | `created_time`, `updated_time` 추가 | 1f1263217 #6443 |
| `db_root` | `R:…authenticate_context.cpp:340-343` | `D:…authenticate_context.cpp:330-333` | 동일(`triggers, charset, lang, timezone_checksum`) | — |
| `db_user`→`_db_user` | `R::407-414` (8, `name string`) | `D::367-378` (12) | `name`이 `varchar(32)`로 바뀜. `triggers` 뒤에 `is_loginable int`, `is_system_created int` 추가. 끝에 `created_time`, `updated_time` 추가 | 1f1263217 #6443, 8ba543178 #6903 |
| `db_password`→`_db_password` | `R::453` (1) | `D::417-421` (4) | `created_time`, `updated_time`, `expire_time` 추가 | 8ba543178 #6903 |
| `db_authorization`→`_db_authorization` | `R::475-476` | `D::443-444` | 동일(`owner`, `grants`) | — |
| — | — | `_db_histogram` `D::1278`: `class_of object, key_attr varchar(255), with_fullscan int, null_frequency double, histogram_values varbit`. UNIQUE `{class_of,key_attr}` | 신규 | aabba8d1e #7180 |
| — | — | `_db_global_tran` `D::1308`: `gtrid int, bqual int, conn_url varchar(512), user_name varchar(32), password varchar(256), state varchar(1), created_time, updated_time` | 신규 | e651ed803 #6820 |

ct 쪽 대응(catcls 내부 칼럼 순서)은 `D:src/object/transform.c:286-437`과 그 diff(`git diff origin/release/11.4..5b1867174 -- src/object/transform.c`)에 있습니다. 같은 diff에서 **클래스 객체 내부의 partition 메타 속성**에도 `class_partition_type`이 추가된 것이 보입니다(`D:transform.c:239-245`). 이것은 클래스 객체 포맷이 바뀐 것이므로 이 티켓이 아니라 클래스 객체 변환 티켓에서 다뤄야 합니다.

## 3. develop 카탈로그 행 레이아웃 (계산)

### 3.1 계산 규칙

- 인스턴스 속성의 디스크 순서는 다음과 같습니다. 고정 길이 속성을 먼저 놓고 `order_atts_by_alignment`로 정렬합니다. 정렬 기준은 정렬 단위 내림차순, 같으면 디스크 크기 오름차순, 그것도 같으면 정의 순서입니다. 그 뒤에 가변 길이 속성을 정의 순서대로 놓습니다(`D:src/object/schema_manager.c:9962-9991, 10022-10126`).
- 새로 만든 클래스는 기존 속성이 없으므로 정의 순서가 곧 입력 순서입니다. develop 카탈로그 클래스는 템플릿 하나로 모든 칼럼을 추가합니다(`system_catalog_builder::build_class`, `D:src/object/schema_system_catalog_builder.cpp:76-118`).
- 고정 영역은 크기를 더한 뒤 4바이트 경계로 올림합니다(`D:src/object/class_object.c:7279-7292`, `DB_ATT_ALIGN` `D:src/base/memory_alloc.h:100`).
- 타입 정보(`PR_TYPE {variable_p, disksize, alignment}`): integer는 고정/4/4, object·datetime·double·bigint는 고정/8/4입니다(`D:src/object/object_primitive.c:938,988,1038,1163,1298`). numeric은 develop에서 `variable_p=1, align 1`(`D:object_primitive.c:1655-1656`)이고 11.4에서는 `variable_p=0, align 1`, 디스크 크기 16(`R:…object_primitive.c:1693-1694`, `OR_NUMERIC_SIZE`=`DB_NUMERIC_BUF_SIZE`=16, `R:…object_primitive.c:119`, `R:src/compat/dbtype_def.h:595`)입니다. string·varchar·sequence·varbit는 가변입니다.
- catcls가 쓰는 행의 바이트 배치(`catcls_put_or_value_into_buffer`, `D:src/storage/catalog_class.c:3203-3324`)는 다음과 같습니다.
  1. 헤더 `int repid_bits`: repid, `n_fixed>0`이면 `OR_BOUND_BIT_FLAG`, 가변 오프셋 크기 `BIG_VAR_OFFSET_SIZE`(4), `OR_MVCC_FLAG_VALID_INSID`.
  2. `int chn`.
  3. `bigint MVCCID_NULL`. 헤더 합계 16바이트(`OR_MVCC_INSERT_HEADER_SIZE`, `D:src/base/object_representation_constants.h:148`).
  4. 가변 오프셋 테이블 `4×(n_var+1)`을 4바이트로 올림(`OR_VAR_TABLE_SIZE`, `D:src/base/object_representation.h:496-500`).
  5. 고정 영역. NULL이면 그 자리를 건너뛰고 bound bit를 0으로 둡니다.
  6. `fixed_length`까지 패딩.
  7. bound bits `((n_fixed+31)>>5)*4`바이트(`D:object_representation.h:667`).
  8. 가변 데이터. 오프셋은 **헤더 끝 기준**입니다.

  ct가 아닌 테이블의 행은 일반 객체 쓰기 경로로 기록되므로 오프셋 크기가 1/2/4 중에서 정해집니다(`D:src/object/transform_cl.c:629,667-671`). 4바이트로 써도 플래그에 크기가 기록되므로 읽는 쪽은 문제없습니다.

### 3.2 결과 (develop, 테이블별)

고정 영역 오프셋은 고정 영역 시작 기준입니다. FL = `fixed_length`, BB = bound bit 바이트, VT = 가변 오프셋 테이블 바이트. 모든 값은 계산값입니다.

| 테이블 | n_fix | FL | BB | n_var | VT | 고정 (이름@오프셋(크기)) | 가변 (순서) |
|---|---|---|---|---|---|---|---|
| `_db_class` | 16 | 84 | 4 | 14 | 60 | class_type@0(4), is_system_class@4, inst_attr_count@8, class_attr_count@12, shared_attr_count@16, inst_meth_count@20, class_meth_count@24, collation_id@28, tde_algorithm@32, statistics_strategy@36, flags@40, class_of@44(8), owner@52(8), created_time@60(8), updated_time@68(8), checked_time@76(8) | unique_name, class_name, sub_classes, super_classes, inst_attrs, class_attrs, shared_attrs, inst_meths, class_meths, meth_files, query_specs, indexes, comment, partition |
| `_db_attribute` | 7 | 36 | 4 | 5 | 24 | attr_type@0, def_order@4, data_type@8, is_nullable@12, flags@16, class_of@20(8), from_class_of@28(8) | attr_name, from_attr_name, default_value, domains, comment |
| `_db_domain` | 7 | 36 | 4 | 3 | 16 | data_type@0, prec@4, scale@8, code_set@12, collation_id@16, object_of@20(8), class_of@28(8) | enumeration, set_domains, json_schema |
| `_db_method` | 3 | 20 | 4 | 3 | 16 | meth_type@0, class_of@4(8), from_class_of@12(8) | meth_name, from_meth_name, signatures |
| `_db_meth_sig` | 2 | 12 | 4 | 3 | 16 | arg_count@0, meth_of@4(8) | func_name, return_value, arguments |
| `_db_meth_arg` | 3 | 16 | 4 | 1 | 8 | data_type@0, index_of@4, meth_sig_of@8(8) | domains |
| `_db_meth_file` | 2 | 16 | 4 | 1 | 8 | class_of@0(8), from_class_of@8(8) | path_name |
| `_db_query_spec` | 2 | 16 | 4 | 1 | 8 | class_of@0(8), invalidated_time@8(8) | spec |
| `_db_index` | 16 | 80 | 4 | 4 | 20 | is_unique@0, key_count@4, is_reverse@8, is_primary_key@12, is_foreign_key@16, have_function@20, status@24, delete_rule@28, update_rule@32, referential_match_option@36, index_type@40, options@44, class_of@48(8), referential_class@56(8), created_time@64(8), updated_time@72(8) | index_name, key_attrs, filter_expression, comment |
| `_db_index_key` | 4 | 20 | 4 | 2 | 12 | key_order@0, asc_desc@4, key_prefix_length@8, index_of@12(8) | key_attr_name, func |
| `_db_partition` | 3 | 16 | 4 | 4 | 20 | ptype@0, class_partition_type@4, class_of@8(8) | pname, pexpr, pvalues, comment |
| `_db_auth` | 7 | 48 | 4 | 1 | 8 | object_type@0, is_grantable@4, grantor@8(8), grantee@16(8), object_of@24(8), created_time@32(8), updated_time@40(8) | auth_type |
| `_db_trigger` | 12 | 68 | 4 | 6 | 28 | status@0, event@4, target_class_attribute@8, condition_type@12, condition_time@16, action_type@20, action_time@24, owner@28(8), priority@36(8), target_class@44(8), created_time@52(8), updated_time@60(8) | unique_name, name, target_attribute, condition, action_definition, comment |
| `_db_data_type` | 1 | 4 | 4 | 1 | 8 | type_id@0 | type_name |
| `_db_stored_procedure` | 10 | 52 | 4 | 7 | 32 | sp_type@0, return_type@4, arg_count@8, lang@12, is_system_generated@16, directive@20, sql_data_access@24, owner@28(8), created_time@36(8), updated_time@44(8) | unique_name, sp_name, args, pkg_name, target_class, target_method, comment |
| `_db_stored_procedure_args` | 6 | 28 | 4 | 3 | 16 | index_of@0, is_system_generated@4, data_type@8, mode@12, is_optional@16, sp_of@20(8) | arg_name, default_value, comment |
| `_db_stored_procedure_code` | 5 | 24 | 4 | 4 | 20 | is_static@0, is_system_generated@4, stype@8, otype@12, owner@16(8) | name, created_time, scode, ocode |
| `_db_serial` | 6 | 36 | 4 | 10 | 44 | cyclic@0, started@4, cached_num@8, owner@12(8), created_time@20(8), updated_time@28(8) | unique_name, name, **current_val, increment_val, max_val, min_val, start_val**, class_name, attr_name, comment |
| `_db_collation` | 6 | 24 | 4 | 2 | 12 | coll_id@0, charset_id@4, built_in@8, expansions@12, contractions@16, uca_strength@20 | coll_name, checksum |
| `_db_charset` | 3 | 12 | 4 | 1 | 8 | charset_id@0, default_collation@4, char_size@8 | charset_name |
| `dual` | 0 | 0 | 0 | 1 | 8 | — | dummy |
| `_db_synonym` | 5 | 36 | 4 | 5 | 24 | is_public@0, owner@4(8), target_owner@12(8), created_time@20(8), updated_time@28(8) | unique_name, name, target_unique_name, target_name, comment |
| `_db_server` | 5 | 36 | 4 | 7 | 32 | port@0, owner@4(8), created_time@12(8), updated_time@20(8), invalidated_time@28(8) | link_name, host, db_name, user_name, password, properties, comment |
| `_db_histogram` | 3 | 20 | 4 | 2 | 12 | with_fullscan@0, class_of@4(8), null_frequency@12(8) | key_attr, histogram_values |
| `_db_global_tran` | 4 | 24 | 4 | 4 | 20 | gtrid@0, bqual@4, created_time@8(8), updated_time@16(8) | conn_url, user_name, password, state |
| `db_root` | 1 | 4 | 4 | 3 | 16 | charset@0 | triggers, lang, timezone_checksum |
| `_db_user` | 7 | 44 | 4 | 5 | 24 | id@0, is_loginable@4, is_system_created@8, password@12(8), authorization@20(8), created_time@28(8), updated_time@36(8) | name, direct_groups, groups, triggers, comment |
| `_db_password` | 3 | 24 | 4 | 1 | 8 | created_time@0(8), updated_time@8(8), expire_time@16(8) | password |
| `_db_authorization` | 1 | 8 | 4 | 1 | 8 | owner@0(8) | grants |

`_db_ha_apply_info`는 HA가 범위 밖이므로 계산하지 않았습니다.

11.4의 `db_serial`은 numeric 칼럼 4개(`current_val, increment_val, max_val, min_val`)가 고정 영역(정렬 단위 1, 각 16바이트, 4바이트 정렬 칼럼 뒤)에 있었습니다(계산, §3.1 규칙). develop에서는 이 칼럼들이 가변 영역으로 옮겨집니다. 이 표는 Rust 구현의 **교차 검증용**입니다. 실제로 쓸 때는 도착 클래스 객체와 representation(DISK_REPR)에서 `n_fixed`/`fixed[]`/`variable[]`/`fixed_length`와 repid를 읽어 써야 합니다. catcls 자신도 그렇게 합니다(`catcls_reorder_attributes_by_repr`, `D:catalog_class.c:2991-3070`).

## 4. CBRD-26459 `cubrid upgradedb`와 versioned 스크립트 체인

| 항목 | 값 | 근거 |
|---|---|---|
| 목표 버전 | `SYSTEM_METADATA_VERSION 1` | `D:src/object/system_metadata_version.h:32` |
| 버전 저장 위치 | `LOG_HEADER.sysmeta_version` (UINT16) | `D:src/transaction/log_storage.hpp:137` |
| 11.4의 같은 바이트 | `INT8 dummy3; INT8 dummy4;` (값 0) | `git diff origin/release/11.4..5b1867174 -- src/transaction/log_storage.hpp` |
| 오프셋 (계산) | 102 (magic[25]@0, pad 3, cdc@28, db_creation@32, vol_creation@40, db_release[15]@48, pad 1, float@64, iopagesize@68, logpagesize@70, is_shutdown@72, pad 3, next_trid@76, mvcc_next_id@80, avg_ntrans@88, avg_nlocks@92, npages@96, db_charset@100, was_copied@101, **sysmeta_version@102**, fpageid@104) | `D:log_storage.hpp:113-138`, `REL_MAX_RELEASE_LENGTH 15` `D:src/base/release_string.h:31`, `CUBRID_MAGIC_MAX_LENGTH 25` `D:src/storage/storage_common.h:414`, `INT8`=int8_t/char `D:include/system.h:116,120` |
| createdb 값 | `SYSTEM_METADATA_VERSION` | `D:src/transaction/log_page_buffer.c:1380` |
| 부팅 검사 | `!= SYSTEM_METADATA_VERSION`이면 `ER_SYSMETA_UPGRADE_REQUIRED`(작으면) 또는 `…DOWNGRADE_NOT_SUPPORTED`(크면) | `D:src/transaction/boot_sr.c:2608-2614` |
| v0 거부 | `current_version == 0`이면 `UPGRADEDB_MSG_NOT_UPGRADABLE` | `D:src/executables/util_sa.c:5704-5717` |
| 스크립트 | `upgrade/v<N>_to_v<N+1>.sql`. 체인은 `v1_to_v2`부터 연속이어야 하고 빌드할 때 SHA256으로 검증. **현재 0개** (`git ls-files upgrade` = `CMakeLists.txt, README.md, upgrade_checksums.h.cmake`) | `D:upgrade/CMakeLists.txt:16-60`, `D:upgrade/README.md` |
| 스크립트 범위 | 클래스 추가와 칼럼 추가·삭제·변경만 가능. 클래스 삭제·이름 변경은 범위 밖 | 9ee8bac8b 커밋 메시지 (#7773) |
| 실행 순서 | 다음 표 참고 | `D:util_sa.c:5704-5790` |

upgradedb 실행 순서:

| 단계 | 함수 | 근거 |
|---|---|---|
| 1 | `upgradedb_truncate_catalog_classes`: `ct_Classes` 11개 truncate | `D:util_sa.c:5285` |
| 2 | 스크립트 실행 | |
| 3 | `catcls_rebuild_vclasses` + `info_schema_rebuild_vclasses`: vclass를 같은 OID에서 다시 정의 | `D:…install.cpp:392-426` |
| 4 | `upgradedb_drop_catalog_class_representations`: ct 11개의 이전 representation 삭제 | `D:util_sa.c:5341` |
| 5 | `upgradedb_rebuild_catalog` = `sm_mark_system_classes` → `catcls_compile_catalog_classes` → `sm_force_write_all_classes` → `au_force_write_new_auth` → `sm_update_all_catalog_statistics` | `D:util_sa.c:5366-5380` |
| 6 | `upgradedb_update_and_log_version` | `D:util_sa.c:5383` |

이 절의 결론은 다음과 같습니다.

- 11.4 → develop에는 엔진이 제공하는 SQL 체인이 없습니다. Rust가 develop v1 카탈로그를 직접 구성해야 합니다.
- 다음 버전(v2 이상)이 나오면 Rust가 v1으로 만든 DB에 `cubrid upgradedb`를 쓸 수 있습니다. 즉 Rust의 목표는 "v1 카탈로그"로 고정할 수 있습니다.
- upgradedb의 5단계 순서는 Rust가 ct 테이블과 `_db_auth`를 다시 만드는 방법의 모델입니다. 클래스 객체에서 ct를 다시 쓰고(`sm_force_write_all_classes`), `_db_authorization.grants`에서 `_db_auth`를 다시 씁니다(`au_force_write_new_auth`, `D:src/object/authenticate_grant.cpp:2111-2200`).

## 5. Rust가 생성해야 하는 행의 종류

| 종류 | 테이블 | 만드는 방법 | 근거 |
|---|---|---|---|
| A. ct 파생 행 (변환하지 않고 생성) | `_db_class, _db_attribute, _db_domain, _db_method, _db_meth_sig, _db_meth_arg, _db_meth_file, _db_query_spec, _db_index, _db_index_key, _db_partition` | 도착(develop) 클래스 객체마다(사용자 클래스, 사용자 vclass, 시스템 클래스, 시스템 vclass 모두) develop의 `catcls_get_or_value_from_class` → `catcls_insert_instance` 의미 그대로 생성 | `ct_Classes[]` `D:src/object/transform.c:529-541`; `D:catalog_class.c:984-1249, 3835-3963` |
| B. 원본 행 재인코딩 | `_db_user, _db_password, _db_authorization, db_root(1행), _db_trigger, _db_serial, _db_stored_procedure, _db_stored_procedure_args, _db_stored_procedure_code, _db_synonym, _db_server` | 11.4 행을 원본 DISK_REPR로 디코드하고, 칼럼 매핑과 새 칼럼 값(§7)을 적용해 develop DISK_REPR로 인코드 | §2 |
| C. 다시 파생 | `_db_auth` | 각 `_db_authorization` 행의 `grants`(4개 단위: type, object, grantor, cache)에서 생성. grantee는 해당 행의 `owner` | `D:authenticate_grant.cpp:2111-2200`, `GRANT_ENTRY_*` `D:src/object/authenticate_grant.hpp:66-71` (11.4와 같음) |
| D. 정적 행 (도착 엔진 기준) | `_db_data_type`(28행), `_db_charset`, `_db_collation`, `dual`(1행 `'X'`) | develop의 `catcls_add_data_type`, `catcls_add_charsets`, `catcls_add_collations`, `catcls_add_dual`로 생성(`D:…install.cpp:79-262`). `_db_collation`은 출발 DB와 같은 locale 라이브러리를 전제합니다. built-in collation ID는 language_support의 11.4→develop diff에서 변경된 줄을 찾지 못했습니다(grep) | |
| E. 새 테이블, 비어 있음 | `_db_histogram`, `_db_global_tran` | 행 0개. 통계는 나중에 다시 수집 | |
| F. 새 시스템 객체 | 사용자 `INFORMATION_SCHEMA`(`_db_user` 행, `_db_authorization` 행, 비밀번호 없음), develop 시스템 vclass 44개(클래스 객체, representation, A의 행), `INFORMATION_SCHEMA` 권한 grants | `D:authenticate_context.cpp:984-1008`, `D:…install.cpp:301-325` | |
| G. 삭제 | `db_authorizations` 클래스(객체, heap, representation), 11.4 시스템 vclass 20개(develop 이름으로 다시 만듦), 11.4 시스템 클래스에 걸린 PUBLIC grant 가운데 develop에 없는 것 | `R:…authenticate_context.cpp:532-536,1029` 대 `D:…authenticate_context.cpp:963-981,1087-1107` | |
| (범위 밖) | `_db_ha_apply_info` | HA 범위 밖. 행 0개로 시작할지는 §8 | map #472 Notes |

## 6. 카탈로그 내부 OID 참조 그래프

종류 표기:

- **raw**: 클래스 OID(root heap 슬롯), 또는 원본 행 OID를 그대로 저장한 것입니다.
- **row**: 카탈로그 행 OID입니다.
- **back**: 부모 행 역참조로, `catcls_insert_instance`가 각 서브셋 항목의 0번 칼럼에 부모 행 OID를 씁니다(`D:catalog_class.c:3871-3893`).
- **conv**: `catcls_convert_class_oid_to_oid`가 클래스 OID를 그 클래스의 `_db_class` 행 OID로 바꾼 값입니다(`D:catalog_class.c:723-805`).

| 출발 (테이블.칼럼) | 도착 | 종류 | 근거 |
|---|---|---|---|
| `_db_class.class_of` | 클래스 객체 OID | raw | `D:catalog_class.c:1076-1084` |
| `_db_class.owner` | `_db_user` 행 | raw (클래스 객체 owner 복사) | `:1050-1051` |
| `_db_class.sub_classes / super_classes` | `_db_class` 행들 | conv | `:1093-1105`, `catcls_get_object_set` `:2813-2863` |
| `_db_class.inst_attrs / class_attrs / shared_attrs` → `_db_attribute.class_of` | `_db_class` 행 | 정방향 시퀀스 / back | `:1108-1132`, `:3871-3893` |
| `_db_attribute.from_class_of` | `_db_class` 행. 자기 클래스면 NULL | conv. self는 NULL 처리 | `:1306-1310`, `:3876-3888` |
| `_db_attribute.domains` → `_db_domain.object_of` | `_db_attribute`, `_db_meth_arg`, `_db_domain` 행 | 정방향 / back | |
| `_db_domain.class_of` | `_db_class` 행. 자기 참조(`class x (a x)`)면 루트 `_db_class` 행 | conv / `DB_TYPE_VARIABLE`를 루트 OID로 | `:1717-1748`, `:3902-3906` |
| `_db_domain.set_domains` | `_db_domain` 행들 | 정방향 | |
| `_db_class.inst_meths / class_meths` → `_db_method.class_of`, `from_class_of` | `_db_class` 행 | back / conv | `:1846-1852` |
| `_db_method.signatures` → `_db_meth_sig.meth_of` → `return_value/arguments` → `_db_meth_arg.meth_sig_of` | 행 | 정방향 / back | |
| `_db_class.meth_files` → `_db_meth_file.class_of`, `from_class_of` | 행 | back / conv | `:2075-2081` |
| `_db_class.query_specs` → `_db_query_spec.class_of` | 행 | back | |
| `_db_class.indexes` → `_db_index.class_of` | 행 | back | |
| `_db_index.key_attrs` → `_db_index_key.index_of` | 행 | back | |
| `_db_index.referential_class` | 참조 대상 클래스 OID (FK 속성 슬롯 0의 문자열 OID) | raw | `:2336-2361`; 1c5f1fd26 #7874 |
| `_db_class.partition` → `_db_partition.class_of` | 행 | back | `:1219-1226` |
| `_db_user.password` | `_db_password` 행 | row | `D:authenticate_context.cpp:369` |
| `_db_user.direct_groups / groups` | `_db_user` 행들 | row | `:370-371` |
| `_db_user.authorization` | `_db_authorization` 행 | row | `:372` |
| `_db_user.triggers` | `_db_trigger` 행들 | row | `:373` |
| `_db_authorization.owner` | `_db_user` 행 (= grantee) | row | `:443`, `D:authenticate_grant.cpp:2154-2159` |
| `_db_authorization.grants[i+1]` | 클래스 OID 또는 `_db_stored_procedure` 행 | raw / row | `D:authenticate_grant.hpp:69`, `D:authenticate_access_auth.cpp:162-187` |
| `_db_authorization.grants[i+2]` | `_db_user` 행 (grantor) | row | `:70` |
| `_db_auth.grantor / grantee` | `_db_user` 행 | row | `D:authenticate_access_auth.cpp:156-160` |
| `_db_auth.object_of` | 클래스 OID (`object_type`=class) 또는 `_db_stored_procedure` 행 | raw / row | `:162-187` |
| `db_root.triggers` (`sequence of (string, object)`) | `_db_trigger` 행 | row | `D:authenticate_context.cpp:330` |
| `_db_trigger.owner` | `_db_user` 행 | row | `D:…install.cpp:828` |
| `_db_trigger.target_class` | 클래스 OID | raw | `:833` |
| `_db_serial.owner`, `_db_stored_procedure.owner`, `_db_stored_procedure_code.owner`, `_db_synonym.owner/target_owner`, `_db_server.owner` | `_db_user` 행 | row | §2 각 정의 |
| `_db_stored_procedure.args` → `_db_stored_procedure_args.sp_of` | 행 / 역참조 | row | `D:…install.cpp:926, 961` |
| `_db_histogram.class_of` | 클래스 OID | raw | `D:…install.cpp:1286` |
| 클래스 객체 `owner` | `_db_user` 행 | row (클래스 객체 쪽) | `D:catalog_class.c:1052` (같은 필드를 읽음) |
| 클래스 객체 trigger 목록 (`ORC_TRIGGERS_INDEX`, 속성별 `ORC_ATT_TRIGGER_INDEX`) | `_db_trigger` 행 | row (클래스 객체 쪽) | `D:transform_cl.c:3089, 4155` |
| 속성 auto_increment | `_db_serial` 행. **디스크에 저장하지 않고 로드할 때 이름으로 찾음** | 이름 | `D:transform_cl.c:4174-4210` |
| 이름(문자열) 참조 | `_db_serial.class_name/attr_name`, `_db_synonym.target_unique_name`, `_db_stored_procedure.target_class` ↔ `_db_stored_procedure_code.name` | 문자열 | §2 |

카탈로그 바깥으로 나가는 **행 OID** 참조는 §0 7번에 적은 세 종류뿐입니다. 클래스 객체의 owner·trigger 목록, `db_root.triggers`, `_db_user.triggers`, `_db_auth`/`grants`의 SP 행이 그것입니다. 사용자 힙의 OBJECT 칼럼이 시스템 클래스 인스턴스를 가리키는 경우는 조사하지 않았습니다(§8).

## 7. Rust가 구현할 규칙 (기계적 검사)

- **R1 (버전 스탬프)**: 도착 로그 헤더의 오프셋 102(계산)에 UINT16 `1`을 씁니다. 그 뒤 `read_u16(102) == 1`인지 검사합니다. 출발 11.4의 같은 2바이트는 0입니다(dummy3/4). 근거는 §4입니다.
- **R2 (ct 칼럼 존재)**: `ct_Classes`의 11개 클래스 각각에 대해, 도착 클래스 객체에 `ct_*_atts`의 모든 칼럼 이름(`D:transform.c:286-437`)이 attr id로 존재해야 합니다. 하나라도 없으면 부팅이 `ER_BO_MISSING_OR_INVALID_CATALOG`로 실패합니다(`catcls_compile_catalog_classes`, `D:catalog_class.c:4737-4844`; `D:boot_sr.c:2616-2623`).
- **R3 (시각 칼럼은 고정 영역)**: 도착 `_db_class` DISK_REPR의 `fixed[]`에 `created_time, updated_time, checked_time, statistics_strategy`가 있어야 하고, `_db_index`의 `fixed[]`에 `created_time, updated_time`이 있어야 합니다(`catcls_cache_fixed_attr_indexes`가 assert, `D:catalog_class.c:4647-4729`). §3.2의 계산과도 일치하는지 확인합니다.
- **R4 (ct는 생성)**: 11.4의 ct 행은 읽기만 합니다(검증용 비교). 도착 ct 행 집합은 도착 클래스 객체 전체에 develop catcls 규칙을 적용한 결과와 같아야 합니다. 11.4 ct 행을 복사하면 틀리는 이유는 두 가지입니다.
  - 11.4는 `is_system_class`에 클래스 flags 정수 전체를 넣었습니다(`R:src/storage/catalog_class.c:1051`; develop은 `D:catalog_class.c:1041-1045`). develop은 bit0만 `is_system_class`에 넣고 나머지 비트는 `flags`에 넣습니다.
  - `default_value`를 자르는 길이가 255에서 2048로 바뀌었습니다(`D:catalog_class.c:1576`).
- **R5 (ct 행 내용 규칙)**: 다음 다섯 가지를 지킵니다.
  - (a) 서브셋 항목의 0번 칼럼은 부모 행 OID입니다.
  - (b) `_db_class` 행의 서브셋 안에서 값이 그 `_db_class` 행 자신의 OID와 같은 OID 칼럼은 NULL로 둡니다.
  - (c) `_db_domain.class_of`가 자기 참조이면 루트 `_db_class` 행 OID를 넣습니다.
  - (d) `_db_class.class_of`와 `_db_index.referential_class`는 raw 클래스 OID를 넣습니다.
  - (e) `_db_class`와 `_db_index` 행의 `created_time`과 `updated_time`은 같은 값으로 넣습니다. catcls는 삽입 시각을 쓰고(`catcls_set_or_value_timestamps` `D:catalog_class.c:4060-4083`), `checked_time`과 `statistics_strategy`는 통계 갱신 때만 씁니다(`:4130-4138`).

  근거: `D:catalog_class.c:3871-3906`.
- **R6 (`_db_index` FK, status, index_type, options)**: develop은 클래스 제약 속성 시퀀스를 끝에서부터 읽습니다. 끝에서 1번째가 comment, 2번째가 options, 3번째가 index_type, 4번째가 status, 5번째가 optional info입니다(`D:src/storage/storage_common.h:1033-1083`, 1f1263217 #6443). FK info는 5칸입니다(ref class OID 문자열, PK BTID, delete, update, match; `:1047-1056`). 11.4는 `key_size-3/-2/-1` = optional/status/comment의 3칸 배치입니다(`R:src/storage/catalog_class.c:2321-2337`). 따라서 **클래스 객체 변환 단계에서 제약 시퀀스에 index_type과 options 슬롯을 끼워 넣어야** 이 규칙이 성립합니다. 클래스 객체 담당 티켓으로 넘기며, 값은 그 티켓에서 확정합니다. 인덱스를 다시 빌드한 뒤에는 FK info의 PK BTID도 새 값으로 바꿔야 합니다.
- **R7 (`_db_partition.class_partition_type`)**: 클래스 객체의 partition 정보에서 `pname == NULL`이면 1(`DB_PARTITIONED_CLASS`), 아니면 2(`DB_PARTITION_CLASS`)입니다. 근거: 11.4가 같은 방식으로 구분합니다(`R:src/object/schema_manager.c:3499`). 열거값은 `D:storage_common.h:1247-1249`, develop 쓰기 쪽은 `D:src/query/execute_schema.c:16356-16365`입니다. 클래스 객체 partition 메타에도 같은 값을 넣습니다(`D:transform_cl.c:4905`, 클래스 객체 티켓).
- **R8 (`_db_user`)**: 행마다 다음 값을 넣습니다.
  - `is_loginable` = 1(이 값이 NULL이거나 0이면 로그인할 수 없습니다. `is_loginable_user` `D:authenticate_context.cpp:1058-1069`).
  - `is_system_created` = 1(DBA·PUBLIC·INFORMATION_SCHEMA) 또는 0(그 외). `get_system_users` `D:src/object/authenticate_context.hpp:213-216`, 새 사용자 기본값 `D:src/object/authenticate_access_user.cpp:438-447`.
  - `created_time`/`updated_time`은 R14를 따릅니다. `name`은 32바이트 이하인지 검사합니다(`varchar(32)`, 11.4 `DB_MAX_USER_LENGTH 32` `R:src/compat/dbtype_def.h:519`).
  - 새 행 `INFORMATION_SCHEMA`: `is_loginable=0`, `is_system_created=1`(`D:authenticate_context.cpp:984-1008`).
- **R9 (grants 재구성)**: 11.4 시스템 클래스와 시스템 vclass에 걸린 grant 항목은 모두 버립니다. develop createdb와 같은 집합을 넣습니다.
  - PUBLIC: `db_root` SELECT|EXECUTE(`D:authenticate_context.cpp:978`), `dual`과 develop 시스템 vclass 각각에 SELECT.
  - INFORMATION_SCHEMA: `db_root`, `_db_user`, `_db_authorization` SELECT(`:999-1001`), 그리고 정의에 `{Au_information_schema_user, AU_SELECT}`가 있는 테이블 전부(`_db_histogram`, `_db_global_tran` 제외).

  사용자 클래스와 SP에 대한 grant 항목은 그대로 옮기되 OID를 매핑합니다. 그다음 `_db_auth`를 C 방식으로 다시 만듭니다. 11.4에는 `_db_authorization`에 PUBLIC EXECUTE grant가 있었지만(`R:…authenticate_context.cpp:1029`) develop에는 없습니다(`D:…:1087-1107`).
- **R10 (`_db_serial`)**: 다음 순서로 처리합니다.
  - (a) 이름을 바꿉니다. 11.4 `db_serial` 클래스 OID를 `_db_serial`로 유지할지는 §8에서 정합니다.
  - (b) numeric 4개를 develop NUMERIC 인코딩(가변)으로 다시 씁니다. 인코딩 자체는 값 인코딩 티켓에서 다룹니다.
  - (c) `start_val` 값은 §8에서 정합니다. 엔진에는 이 값을 읽는 코드가 뷰 외에는 없습니다(`SERIAL_ATTR_START_VAL`을 쓰는 곳은 `D:src/query/execute_statement.c:958` 하나).
  - (d) AUTO_INCREMENT 속성마다 develop 이름 규칙을 적용합니다. `len(class_only)+4+len(attr) < 223`이면 `"<owner>.<class>_ai_<attr>"`로 11.4와 같고, 그렇지 않으면 md5 형태입니다(`set_auto_increment_serial_name` `D:transform.c:667-730`, `DB_MAX_SERIAL_NAME_LENGTH 223` `D:dbtype_def.h:566`; 11.4는 항상 `"%s_ai_%s"` `R:src/object/transform.h:120`). 두 이름이 다르면 `unique_name`과 `name`을 develop 이름으로 바꿉니다. 그러지 않으면 로드할 때 `att->auto_increment`를 찾지 못합니다(`D:transform_cl.c:4190-4210`). 도입 커밋은 217ea8c44 #7230입니다.
- **R11 (`_db_stored_procedure`)**: `sql_data_access`에 -1(`SP_SQL_TYPE_UNKNOWN`)을 넣습니다. develop도 컴파일 응답이 없을 때 이 값을 씁니다(`D:src/sp/jsp_cl.cpp:1195`, 열거값 `D:src/sp/sp_constants.hpp:148-156`). `target_method`는 4096자 이하이므로 11.4 값(1024자 이하)을 그대로 씁니다.
- **R12 (`_db_trigger`)**: 11.4 `db_trigger` 행의 칼럼 16개를 이름으로 매핑하고 시각 칼럼은 R14를 따릅니다. `owner`는 `_db_user` 매핑을 적용하고 `target_class`는 raw를 유지합니다.
- **R13 (`_db_data_type`)**: develop 28행으로 교체합니다. NCHAR(type_id 26)과 VARNCHAR(27) 행은 없습니다(계산: `names[]` 인덱스 25와 26, `type_id = i+1`). `D:…install.cpp:87-123`.
- **R14 (시각 칼럼 정책)**: 원본에 값이 없는 `created_time`/`updated_time`/`invalidated_time`/`expire_time`/`checked_time`에 무엇을 넣을지는 §8의 결정 사항입니다. 엔진 동작에 영향을 주는 것은 `_db_password.expire_time`("not yet implemented", `D:authenticate_context.cpp:420`)과 `checked_time`(통계)뿐입니다. 이 문서 범위에서 찾은 나머지는 뷰 표시용입니다.
- **R15 (시스템 vclass)**: 위 목록의 클래스 객체를 develop 정의와 같게 만듭니다. 이름, 칼럼, query spec 문자열, owner(DBA 또는 INFORMATION_SCHEMA 행), grants가 같아야 합니다. ct 행은 R4로 생성합니다. 검사 방법: 도착 DB에서 엔진 `unloaddb` 스키마 출력에 시스템 vclass가 나오지 않는지 확인하고, 템플릿 develop DB와 `db_vclass.vclass_def`를 집합 비교합니다.
- **R16 (OID 재매핑 폐포)**: 카탈로그 행을 새 페이지에 할당하면 old→new 맵을 하나 만듭니다. 그다음 §6의 row 종류 칼럼, 클래스 객체 owner·trigger 목록, `db_root.triggers`, `grants`에 맵을 적용합니다. 검사 조건: 도착 DB의 모든 OBJECT 값과 시퀀스 원소 가운데 카탈로그 행을 가리키는 것은, 가리키는 슬롯에 그 클래스의 살아 있는 행이 있어야 합니다(검증기의 카탈로그 참조 검사).
- **R17 (클래스 OID 캐시 이름)**: `oid_Cache`의 이름 28개(`D:src/storage/oid.c:87-117`)가 모두 도착 root heap에서 이름으로 찾아져야 합니다. 부팅할 때 `catcls_find_and_set_cached_class_oid`가 이름으로 찾습니다(`D:catalog_class.c:5631-5650`). 클래스 OID 자체를 고정으로 가정하는 코드는 없고 모두 이름으로 찾습니다(`D:oid.c:41-69`는 0으로 초기화).
- **R18 (`db_root`)**: `charset`, `lang`, `timezone_checksum` 값을 그대로 둡니다. 부팅할 때 이 값을 읽어 호환성을 검사합니다(`catcls_get_server_compat_info` `D:catalog_class.c:4860-5051`).

## 8. 열린 질문

1. ct가 아닌 카탈로그 테이블(§5 B)도 지도 Notes 결정대로 "옛 페이지 해제 후 새로 할당"할지 정해야 합니다. 사용자 힙처럼 "같은 슬롯에 재기록하고 커지면 REC_RELOCATION"으로 두면 R16의 외부 참조 재매핑(클래스 객체 owner·triggers, grants의 SP 행)이 필요 없습니다. 이 경우 `db_serial` → `_db_serial`처럼 클래스 OID를 유지하고 이름만 바꾸면 됩니다. develop의 새 vclass `db_serial`, `db_user`, `db_trigger`, `db_authorization`, `db_ha_apply_info`에는 새 클래스 OID가 필요합니다.
2. `_db_serial.start_val`, 그리고 R14의 시각 칼럼에 넣을 값(NULL, 기본값 1, `current_val` 중 무엇, 또는 마이그레이션 시각)을 정해야 합니다. 엔진 동작에는 영향이 없으므로 `INFORMATION_SCHEMA.sequences`나 `db_serial` 출력을 기준으로 정하면 됩니다.
3. 시스템 vclass 44개와 `INFORMATION_SCHEMA` 사용자를 어떻게 공급할지 정해야 합니다. 같은 charset/locale로 만든 develop 템플릿 DB에서 클래스 객체를 복사하고 OID를 매핑하는 방법과, 정의(`*_query_spec.cpp`)를 Rust에 박아 넣는 방법이 있습니다. upgradedb도 SQL로 다시 쓰지 않고 바이너리 정의에서 다시 만듭니다(`D:util_sa.c:5309-5317`의 주석). 그러면 템플릿 쪽이 정확도에서 유리합니다. [VERIFY: 템플릿 representation의 repid를 그대로 써도 되는지]
4. 사용자 뷰가 11.4 시스템 클래스와 뷰(`db_user`, `db_trigger`, `db_serial`, `db_trig`, `db_authorizations`)를 참조할 수 있습니다. develop에서는 이 이름들이 칼럼이 다른 뷰가 되거나 사라집니다. 이런 경우 pre-check에서 거부할지 경고만 할지 정해야 합니다. 사용자 힙의 OBJECT 칼럼이 시스템 클래스 인스턴스를 가리키는 경우도 조사하지 않았습니다.
5. 11.4 인덱스에 dedup 숨김 키 속성(`WITH DEDUPLICATE`, 11.4 기본은 비활성 `R:src/object/deduplicate_key.h:43`)이 있으면 develop(5de66400a #8104 제거)에서는 그 attr id를 해석할 수 없습니다(11.4는 `R:src/storage/catalog_class.c:875`에서 dedup attr id를 따로 처리하지만, develop `D:catalog_class.c:878-886`에는 그 분기가 없습니다). 클래스 객체 변환 단계에서 제약의 dedup 항목을 제거해야 하는지 [VERIFY]가 필요합니다.
6. `_db_ha_apply_info` 행: HA가 범위 밖이므로 0행으로 시작해도 되는지 확인이 필요합니다.
7. R6의 index_type과 options 값, 그리고 클래스 객체 partition 메타의 `class_partition_type` 슬롯은 클래스 객체 담당 티켓과 합의해야 합니다.

## 9. 출처

- develop `5b1867174`:
  - `src/object/schema_system_catalog_install.cpp`, `schema_system_catalog_constants.h`, `schema_system_catalog.cpp`, `schema_system_catalog_builder.cpp`, `schema_information_schema_constants.h`
  - `src/storage/catalog_class.c`, `src/object/transform.c`, `transform.h`, `transform_cl.c`, `schema_manager.c`, `class_object.c`, `object_primitive.c`
  - `src/object/authenticate_context.cpp`, `.hpp`, `authenticate_access_user.cpp`, `authenticate_access_auth.cpp`, `authenticate_grant.cpp`, `.hpp`, `trigger_manager.c`
  - `src/storage/storage_common.h`, `oid.c`, `src/base/object_representation.h`, `object_representation_constants.h`, `memory_alloc.h`, `release_string.h`, `src/compat/dbtype_def.h`, `include/system.h`
  - `src/transaction/log_storage.hpp`, `log_page_buffer.c`, `boot_sr.c`, `src/executables/util_sa.c`, `src/object/system_metadata_version.h`, `upgrade/*`
  - `src/sp/sp_constants.hpp`, `jsp_cl.cpp`, `src/query/execute_schema.c`, `execute_statement.c`
- `origin/release/11.4` `46212adcd`: 위 파일의 같은 경로들. 특히 `schema_system_catalog_install.cpp`, `schema_system_catalog_constants.h`, `schema_system_catalog.cpp`, `authenticate_context.cpp`, `trigger_manager.c`, `object_primitive.c`, `dbtype_def.h`, `transform.h`, `schema_manager.c`, `deduplicate_key.h`, `system_parameter.c`.
- 커밋/PR (CUBRID/cubrid):
  - 1f1263217 #6443 (CBRD-25862), 8ba543178 #6903, 601f0c324 #7174 (CBRD-25863), 1c5f1fd26 #7874 (CBRD-27382), 9ee8bac8b #7773 (CBRD-26459), de7bc5ec2 #6486 (CBRD-26006)
  - aabba8d1e #7180 (CBRD-26202), e651ed803 #6820 (CBRD-26291), bb8f3cbda #6420 (CBRD-24156), a38948c99 #6427 (CBRD-26283), 217ea8c44 #7230 (CBRD-26841), 5de66400a #8104 (CBRD-27324), 149cade58 #6925 (CBRD-26633)
- 계산 스크립트: §3.2 표는 §3.1 규칙을 그대로 옮긴 계산 결과입니다(작업 트리의 git-ignored scratch에서 실행했고 커밋하지 않았습니다).
